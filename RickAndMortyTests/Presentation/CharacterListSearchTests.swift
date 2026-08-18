import Foundation
import Testing
@testable import RickAndMorty

// La búsqueda y los filtros tienen su propia suite porque lo que prueban es otra cosa
// que la paginación: allí se comprueba cómo crece la lista, aquí cómo se sustituye
// entera y qué le llega al servidor al hacerlo.
@MainActor
@Suite("Character list search and filters")
struct CharacterListSearchTests {
    // MARK: - Búsqueda

    @Test("Typing waits for the user to stop before asking the server")
    func searchWaitsForTheTypingToSettle() async {
        // La búsqueda es del servidor: sin esta espera, escribir "rick" son cuatro
        // peticiones de las que solo importa la última.
        let waits = SleepRecorder()
        let repository = StubCharacterRepository(characters: .success(.stub(page: 1, totalPages: 1, ids: 1...3)))
        let sut = CharacterListViewModel.forTesting(repository, recordingWaitsInto: waits)
        await sut.onAppear()

        sut.searchText = "rick"
        await sut.searchTask?.value

        #expect(await waits.durations == [.milliseconds(350)])
        #expect(await repository.requestedSearchTerms == ["", "rick"])
    }

    @Test("A keystroke during the wait cancels the search that was waiting; only the last one goes out")
    func onlyTheLastKeystrokeIsSearched() async {
        // Es lo que pasa de verdad al teclear: la búsqueda de "ric" está dentro de la
        // espera cuando llega la "k", y se cancela antes de llegar a salir, así que el
        // servidor solo ve el término completo. La espera se congela en un pestillo para
        // que la segunda tecla llegue con la primera búsqueda de verdad esperando, y no
        // antes de que haya empezado.
        let debounce = AsyncGate()
        let repository = StubCharacterRepository(characters: .success(.stub(page: 1, totalPages: 1, ids: 1...3)))
        let sut = CharacterListViewModel(
            fetchCharacters: FetchCharactersUseCase(repository: repository),
            sleep: { _ in await debounce.wait() }
        )
        await sut.onAppear()

        sut.searchText = "ric"
        await debounce.waitUntilReached()
        sut.searchText = "rick"
        await debounce.open()
        await sut.searchTask?.value

        #expect(await repository.requestedSearchTerms == ["", "rick"])
    }

    @Test("Trailing whitespace is not a new search")
    func whitespaceDoesNotTriggerASearch() async {
        // La barra de búsqueda de iOS reescribe el texto al perder el foco. Sin la
        // comparación sobre el término recortado, eso sería otra petición idéntica.
        let repository = StubCharacterRepository(characters: .success(.stub(page: 1, totalPages: 1, ids: 1...3)))
        let sut = CharacterListViewModel.forTesting(repository)
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
        let sut = CharacterListViewModel.forTesting(repository)
        await sut.onAppear()

        await repository.setCharacters(.success(.empty()), forPage: 1)
        sut.searchText = "zzzz"
        await sut.searchTask?.value

        #expect(sut.state == .empty)
        #expect(sut.isNarrowed)
    }

    @Test("Typing a letter and deleting it within the wait asks for nothing")
    func typingAndDeletingWithinTheWaitDoesNotReload() async {
        // Al final de la espera el criterio vuelve a ser el que ya está pintado, así que
        // no hay nada que recargar: volver a pedirlo era tirar la lista, enseñar el
        // esqueleto, perder el scroll y gastar una petición para acabar donde se estaba
        let repository = StubCharacterRepository(characters: .success(.stub(page: 1, totalPages: 1, ids: 1...3)))
        let sut = CharacterListViewModel.forTesting(repository)
        await sut.onAppear()

        sut.searchText = "r"
        sut.searchText = ""
        await sut.searchTask?.value

        #expect(await repository.requestedPages == [1])
        #expect(sut.state.value?.count == 3)
    }

    @Test("Typing a search does not light up the filters, but it does narrow the list")
    func searchIsNotAFilter() async {
        // La búsqueda tiene su propia barra y su propia forma de borrarse. Contarla como
        // filtro encendía el icono de la hoja al teclear sin haber tocado un filtro, y
        // el "Clear" de la hoja borraba un texto que no está en la hoja.
        let repository = StubCharacterRepository(characters: .success(.stub(page: 1, totalPages: 1, ids: 1...3)))
        let sut = CharacterListViewModel.forTesting(repository)
        await sut.onAppear()

        sut.searchText = "rick"
        await sut.searchTask?.value

        #expect(sut.hasSearchText)
        #expect(!sut.hasActiveFilters)
        #expect(sut.isNarrowed)
    }

    @Test("A search that lands after the user typed something else is not painted")
    func aLateResponseForAnOlderSearchIsDiscarded() async {
        // onlyTheLastKeystrokeIsSearched cubre el caso en que la primera búsqueda ni
        // llega a salir. Aquí sí sale, y llega tarde: la respuesta de "rick" se congela,
        // la de "morty" sale y se pinta, y cuando por fin llega la de "rick" no puede
        // sustituir a la que ya es la buena.
        let gate = AsyncGate()
        let repository = StubCharacterRepository(
            charactersByPage: [1: .success(.stub(page: 1, totalPages: 1, ids: 1...3))]
        )
        let sut = CharacterListViewModel.forTesting(repository)
        await sut.onAppear()

        await repository.holdListings(at: gate)
        sut.searchText = "rick"
        await gate.waitUntilReached()
        let stale = sut.searchTask

        await repository.holdListings(at: nil)
        await repository.setCharacters(.success(.stub(page: 1, totalPages: 1, ids: 100...101)), forPage: 1)
        sut.searchText = "morty"
        await sut.searchTask?.value
        #expect(sut.state.value?.map(\.id) == [100, 101])

        await gate.open()
        await stale?.value

        #expect(await repository.requestedSearchTerms == ["", "rick", "morty"])
        #expect(sut.state.value?.map(\.id) == [100, 101])
    }

    @Test("A page that arrives after the criteria changed does not land on the new list")
    func aLatePageForAnOlderCriterionIsDiscarded() async throws {
        // La página dos de la lista sin filtro sigue en vuelo cuando el usuario elige un
        // filtro. Si aterrizara, se pegaría al final de la lista filtrada: veinte
        // personajes que no cumplen el filtro debajo de tres que sí.
        let gate = AsyncGate()
        let repository = StubCharacterRepository(charactersByPage: [
            1: .success(.stub(page: 1, totalPages: 3, ids: 1...5)),
            2: .success(.stub(page: 2, totalPages: 3, ids: 6...10)),
        ])
        let sut = CharacterListViewModel.forTesting(repository)
        await sut.onAppear()

        await repository.holdListings(at: gate)
        sut.loadNextPageIfNeeded(after: try #require(sut.state.value?.last))
        await gate.waitUntilReached()
        let stalePage = sut.pagingTask

        await repository.holdListings(at: nil)
        await repository.setCharacters(.success(.stub(page: 1, totalPages: 1, ids: 100...102)), forPage: 1)
        sut.statusFilter = .dead
        await sut.searchTask?.value
        #expect(sut.state.value?.map(\.id) == [100, 101, 102])

        await gate.open()
        await stalePage?.value

        #expect(sut.state.value?.map(\.id) == [100, 101, 102])
        #expect(!sut.isLoadingNextPage)
    }

    // MARK: - Filtros

    @Test("Typing a species waits for the user to stop, like the search does")
    func speciesWaitsForTheTypingToSettle() async {
        // La especie se teclea, no se elige de una lista: sin la espera, "Human" serían
        // cinco peticiones de las que solo importa la última
        let waits = SleepRecorder()
        let repository = StubCharacterRepository(characters: .success(.stub(page: 1, totalPages: 1, ids: 1...3)))
        let sut = CharacterListViewModel.forTesting(repository, recordingWaitsInto: waits)
        await sut.onAppear()

        sut.speciesFilter = "Human"
        await sut.searchTask?.value

        #expect(await waits.durations == [.milliseconds(350)])
        #expect(await repository.requestedFilters.map(\.trimmedSpecies) == ["", "Human"])
        #expect(sut.hasActiveFilters)
    }

    @Test("Choosing a filter asks the server straight away, with no typing to wait for")
    func filtersDoNotWait() async {
        // Un filtro se toca una vez, no se teclea: no hay ninguna tecla siguiente que
        // esperar, así que hacerle esperar al usuario sería latencia regalada.
        let waits = SleepRecorder()
        let repository = StubCharacterRepository(characters: .success(.stub(page: 1, totalPages: 1, ids: 1...3)))
        let sut = CharacterListViewModel.forTesting(repository, recordingWaitsInto: waits)
        await sut.onAppear()

        sut.statusFilter = .alive
        await sut.searchTask?.value

        #expect(await waits.durations.isEmpty)
        #expect(await repository.requestedFilters.last?.status == .alive)
    }

    @Test("Every active criterion reaches the repository together")
    func criteriaTravelTogether() async {
        let repository = StubCharacterRepository(characters: .success(.stub(page: 1, totalPages: 1, ids: 1...3)))
        let sut = CharacterListViewModel.forTesting(repository)
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
        let sut = CharacterListViewModel.forTesting(repository)
        await sut.onAppear()
        try await sut.scrollToTheEnd()
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
        let sut = CharacterListViewModel.forTesting(repository)
        await sut.onAppear()
        sut.statusFilter = .alive
        await sut.searchTask?.value

        try await sut.scrollToTheEnd()

        #expect(await repository.requestedFilters.last?.status == .alive)
        #expect(await repository.requestedPages == [1, 1, 2])
    }

    @Test("Clearing the filters keeps the search and asks the server again")
    func clearingFiltersReloads() async {
        // La búsqueda no es un filtro de la hoja: tiene su propia barra y su propia
        // forma de borrarse, así que "Clear" no puede llevársela por delante
        let repository = StubCharacterRepository(characters: .success(.stub(page: 1, totalPages: 1, ids: 1...3)))
        let sut = CharacterListViewModel.forTesting(repository)
        await sut.onAppear()
        sut.searchText = "rick"
        sut.statusFilter = .alive
        await sut.searchTask?.value

        sut.clearFilters()
        await sut.searchTask?.value

        #expect(!sut.hasActiveFilters)
        #expect(await repository.requestedFilters.last == CharacterFilter(name: "rick"))
    }

    @Test("Clearing filters that were already empty asks for nothing")
    func clearingNothingDoesNothing() async {
        // El botón de limpiar sigue existiendo aunque no haya nada puesto; tocarlo no
        // puede costar una recarga completa de la lista.
        let repository = StubCharacterRepository(characters: .success(.stub(page: 1, totalPages: 1, ids: 1...3)))
        let sut = CharacterListViewModel.forTesting(repository)
        await sut.onAppear()

        sut.clearFilters()
        await sut.searchTask?.value

        #expect(await repository.requestedPages == [1])
    }

    @Test("The empty screen's action clears the search and the filters together and asks again")
    func clearingSearchAndFiltersReloadsWithNothing() async {
        // Es lo que ofrece la pantalla vacía: quitar todo lo que acota, la búsqueda
        // incluida, y volver a la lista entera
        let repository = StubCharacterRepository(characters: .success(.stub(page: 1, totalPages: 1, ids: 1...3)))
        let sut = CharacterListViewModel.forTesting(repository)
        await sut.onAppear()
        sut.searchText = "rick"
        sut.statusFilter = .alive
        sut.speciesFilter = "Human"
        await sut.searchTask?.value

        sut.clearSearchAndFilters()
        await sut.searchTask?.value

        #expect(!sut.isNarrowed)
        #expect(sut.searchText.isEmpty)
        #expect(await repository.requestedFilters.last == .empty)
    }

    @Test("Clearing search and filters when nothing narrows the list asks for nothing")
    func clearingSearchAndFiltersWhenNothingIsNarrowedDoesNothing() async {
        let repository = StubCharacterRepository(characters: .success(.stub(page: 1, totalPages: 1, ids: 1...3)))
        let sut = CharacterListViewModel.forTesting(repository)
        await sut.onAppear()

        sut.clearSearchAndFilters()
        await sut.searchTask?.value

        #expect(await repository.requestedPages == [1])
    }

    @Test("A refresh keeps the filter the user is looking at")
    func refreshKeepsTheFilter() async {
        let repository = StubCharacterRepository(characters: .success(.stub(page: 1, totalPages: 1, ids: 1...3)))
        let sut = CharacterListViewModel.forTesting(repository)
        await sut.onAppear()
        sut.searchText = "rick"
        await sut.searchTask?.value

        await sut.refresh()

        #expect(await repository.requestedSearchTerms == ["", "rick", "rick"])
    }
}
