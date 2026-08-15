import Foundation
import Testing
@testable import RickAndMorty

// La búsqueda y los filtros tienen su propia suite porque lo que prueban es otra cosa
// que la paginación: allí se comprueba cómo crece la lista, aquí cómo se sustituye
// entera y qué le llega al servidor al hacerlo.
@MainActor
@Suite("Character list search and filters")
struct CharacterListSearchTests {
    private func makeSUT(
        _ repository: StubCharacterRepository,
        recordingWaitsInto recorder: SleepRecorder? = nil
    ) -> CharacterListViewModel {
        CharacterListViewModel(
            fetchCharacters: FetchCharactersUseCase(repository: repository),
            sleep: { await recorder?.record($0) }
        )
    }

    // MARK: - Búsqueda

    @Test("Typing waits for the user to stop before asking the server")
    func searchWaitsForTheTypingToSettle() async {
        // La búsqueda es del servidor: sin esta espera, escribir "rick" son cuatro
        // peticiones de las que solo importa la última.
        let waits = SleepRecorder()
        let repository = StubCharacterRepository(characters: .success(.stub(page: 1, totalPages: 1, ids: 1...3)))
        let sut = makeSUT(repository, recordingWaitsInto: waits)
        await sut.onAppear()

        sut.searchText = "rick"
        await sut.searchTask?.value

        #expect(await waits.durations == [.milliseconds(350)])
        #expect(await repository.requestedSearchTerms == ["", "rick"])
    }

    @Test("Two keystrokes in a row only ask for the last one")
    func onlyTheLastKeystrokeIsSearched() async {
        // Es lo que pasa de verdad al teclear: la búsqueda anterior se cancela antes de
        // llegar a salir, así que el servidor solo ve el término completo.
        let repository = StubCharacterRepository(characters: .success(.stub(page: 1, totalPages: 1, ids: 1...3)))
        let sut = makeSUT(repository)
        await sut.onAppear()

        sut.searchText = "ric"
        sut.searchText = "rick"
        await sut.searchTask?.value

        #expect(await repository.requestedSearchTerms == ["", "rick"])
    }

    @Test("Trailing whitespace is not a new search")
    func whitespaceDoesNotTriggerASearch() async {
        // La barra de búsqueda de iOS reescribe el texto al perder el foco. Sin la
        // comparación sobre el término recortado, eso sería otra petición idéntica.
        let repository = StubCharacterRepository(characters: .success(.stub(page: 1, totalPages: 1, ids: 1...3)))
        let sut = makeSUT(repository)
        await sut.onAppear()
        sut.searchText = "rick"
        await sut.searchTask?.value

        sut.searchText = "rick "
        await sut.searchTask?.value

        #expect(await repository.requestedPages == [1, 1])
    }

    @Test("A search with no matches is an empty state, not an error")
    func emptySearchResult() async {
        let repository = StubCharacterRepository(
            charactersByPage: [1: .success(.stub(page: 1, totalPages: 1, ids: 1...3))]
        )
        let sut = makeSUT(repository)
        await sut.onAppear()

        await repository.setCharacters(.success(.empty()), forPage: 1)
        sut.searchText = "zzzz"
        await sut.searchTask?.value

        #expect(sut.state == .empty)
        #expect(sut.hasActiveFilters)
    }

    // MARK: - Filtros

    @Test("Choosing a filter asks the server straight away, with no typing to wait for")
    func filtersDoNotWait() async {
        // Un filtro se toca una vez, no se teclea: no hay ninguna tecla siguiente que
        // esperar, así que hacerle esperar al usuario sería latencia regalada.
        let waits = SleepRecorder()
        let repository = StubCharacterRepository(characters: .success(.stub(page: 1, totalPages: 1, ids: 1...3)))
        let sut = makeSUT(repository, recordingWaitsInto: waits)
        await sut.onAppear()

        sut.statusFilter = .alive
        await sut.searchTask?.value

        #expect(await waits.durations.isEmpty)
        #expect(await repository.requestedFilters.last?.status == .alive)
    }

    @Test("Every active criterion reaches the repository together")
    func criteriaTravelTogether() async {
        let repository = StubCharacterRepository(characters: .success(.stub(page: 1, totalPages: 1, ids: 1...3)))
        let sut = makeSUT(repository)
        await sut.onAppear()

        sut.statusFilter = .alive
        await sut.searchTask?.value
        sut.genderFilter = .female
        await sut.searchTask?.value
        sut.speciesFilter = "Human"
        await sut.searchTask?.value

        let last = await repository.requestedFilters.last
        #expect(last?.status == .alive)
        #expect(last?.gender == .female)
        #expect(last?.trimmedSpecies == "Human")
    }

    @Test("A new filter replaces the list instead of appending to it")
    func filteringStartsTheListOver() async throws {
        // Filtrar no es una página más: es otra lista. Si lo cargado no se tirase, el
        // usuario acabaría viendo mezclados los resultados de dos búsquedas distintas.
        let repository = StubCharacterRepository(charactersByPage: [
            1: .success(.stub(page: 1, totalPages: 3, ids: 1...5)),
            2: .success(.stub(page: 2, totalPages: 3, ids: 6...10)),
        ])
        let sut = makeSUT(repository)
        await sut.onAppear()
        try await scrollToTheEnd(of: sut)
        #expect(sut.state.value?.count == 10)

        await repository.setCharacters(.success(.stub(page: 1, totalPages: 1, ids: 100...102)), forPage: 1)
        sut.statusFilter = .dead
        await sut.searchTask?.value

        #expect(sut.state.value?.map(\.id) == [100, 101, 102])
    }

    @Test("The next page is asked for with the filter that is active")
    func paginationKeepsTheFilter() async throws {
        // Si la página dos saliera sin filtro, el scroll acabaría trayendo la lista
        // entera por debajo de una búsqueda: un resultado que el usuario no ha pedido.
        let repository = StubCharacterRepository(charactersByPage: [
            1: .success(.stub(page: 1, totalPages: 3, ids: 1...5)),
            2: .success(.stub(page: 2, totalPages: 3, ids: 6...10)),
        ])
        let sut = makeSUT(repository)
        await sut.onAppear()
        sut.statusFilter = .alive
        await sut.searchTask?.value

        try await scrollToTheEnd(of: sut)

        #expect(await repository.requestedFilters.last?.status == .alive)
        #expect(await repository.requestedPages == [1, 1, 2])
    }

    @Test("Clearing the filters goes back to the unfiltered list")
    func clearingFiltersReloads() async {
        let repository = StubCharacterRepository(characters: .success(.stub(page: 1, totalPages: 1, ids: 1...3)))
        let sut = makeSUT(repository)
        await sut.onAppear()
        sut.searchText = "rick"
        sut.statusFilter = .alive
        await sut.searchTask?.value

        sut.clearFilters()
        await sut.searchTask?.value

        #expect(!sut.hasActiveFilters)
        #expect(await repository.requestedFilters.last == .empty)
    }

    @Test("Clearing filters that were already empty asks for nothing")
    func clearingNothingDoesNothing() async {
        // El botón de limpiar sigue existiendo aunque no haya nada puesto; tocarlo no
        // puede costar una recarga completa de la lista.
        let repository = StubCharacterRepository(characters: .success(.stub(page: 1, totalPages: 1, ids: 1...3)))
        let sut = makeSUT(repository)
        await sut.onAppear()

        sut.clearFilters()
        await sut.searchTask?.value

        #expect(await repository.requestedPages == [1])
    }

    @Test("A refresh keeps the filter the user is looking at")
    func refreshKeepsTheFilter() async {
        let repository = StubCharacterRepository(characters: .success(.stub(page: 1, totalPages: 1, ids: 1...3)))
        let sut = makeSUT(repository)
        await sut.onAppear()
        sut.searchText = "rick"
        await sut.searchTask?.value

        await sut.refresh()

        #expect(await repository.requestedSearchTerms == ["", "rick", "rick"])
    }

    // MARK: - Helpers

    // Simula que aparece la última celda cargada, que es lo que hace el grid al llegar
    // al fondo, y espera a que termine lo que eso haya disparado
    private func scrollToTheEnd(of sut: CharacterListViewModel) async throws {
        let last = try #require(sut.state.value?.last)
        sut.loadNextPageIfNeeded(after: last)
        await sut.pagingTask?.value
    }
}
