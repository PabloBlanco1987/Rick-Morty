import Foundation
import Testing
@testable import RickAndMorty

// @MainActor porque el view model lo es: así los tests llaman a sus métodos desde el
// mismo aislamiento que la vista, y lo que se prueba es el orden real de las cosas.
@MainActor
@Suite("Character list view model")
struct CharacterListViewModelTests {
    // El freno entre páginas se registra en vez de dormirse: la suite se queda en
    // milisegundos y además se puede comprobar que existe
    private func makeSUT(
        _ repository: StubCharacterRepository,
        recordingWaitsInto recorder: SleepRecorder? = nil
    ) -> CharacterListViewModel {
        CharacterListViewModel(
            fetchCharacters: FetchCharactersUseCase(repository: repository),
            sleep: { await recorder?.record($0) }
        )
    }

    private func makeSUT(pages: [Int: Result<Page<Character>, AppError>]) -> (
        CharacterListViewModel, StubCharacterRepository
    ) {
        let repository = StubCharacterRepository(charactersByPage: pages)
        return (makeSUT(repository), repository)
    }

    // MARK: - Carga inicial

    @Test("Starts idle, with nothing loading and no page error")
    func startsIdle() {
        let sut = makeSUT(StubCharacterRepository())

        #expect(sut.state == .idle)
        #expect(!sut.isLoadingNextPage)
        #expect(sut.nextPageError == nil)
    }

    @Test("The first page that arrives becomes the loaded state")
    func loadsFirstPage() async {
        let (sut, repository) = makeSUT(pages: [1: .success(.stub(page: 1, totalPages: 3, ids: 1...5))])

        await sut.onAppear()

        #expect(sut.state.value?.map(\.id) == [1, 2, 3, 4, 5])
        #expect(await repository.requestedPages == [1])
    }

    @Test("A first page with no characters is empty, which is not the same as failed")
    func emptyFirstPage() async {
        let (sut, _) = makeSUT(pages: [1: .success(.empty())])

        await sut.onAppear()

        #expect(sut.state == .empty)
    }

    @Test("Appearing again does not reload what is already on screen")
    func appearingAgainDoesNotReload() async {
        // .task se vuelve a disparar cada vez que la vista aparece. Si eso recargara,
        // volver del detalle costaría la lista entera y la posición del scroll.
        let (sut, repository) = makeSUT(pages: [1: .success(.stub(page: 1, totalPages: 3, ids: 1...5))])

        await sut.onAppear()
        await sut.onAppear()

        #expect(await repository.requestedPages == [1])
    }

    // MARK: - Paginación

    @Test("The next page is appended to what is already on screen")
    func appendsNextPage() async throws {
        let (sut, repository) = makeSUT(pages: [
            1: .success(.stub(page: 1, totalPages: 3, ids: 1...5)),
            2: .success(.stub(page: 2, totalPages: 3, ids: 6...10)),
        ])
        await sut.onAppear()

        try await scrollToTheEnd(of: sut)

        #expect(sut.state.value?.map(\.id) == [1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
        #expect(await repository.requestedPages == [1, 2])
        #expect(!sut.isLoadingNextPage)
    }

    @Test("Two cells appearing at once only ask for the next page once")
    func guardsAgainstDuplicateNextPageLoads() async throws {
        let (sut, repository) = makeSUT(pages: [
            1: .success(.stub(page: 1, totalPages: 3, ids: 1...5)),
            2: .success(.stub(page: 2, totalPages: 3, ids: 6...10)),
        ])
        await sut.onAppear()
        let trigger = try #require(sut.state.value?.last)

        // Las dos llamadas seguidas y sin ningún await entre medias: es exactamente lo
        // que pasa cuando dos celdas del grid aparecen en el mismo ciclo de layout.
        sut.loadNextPageIfNeeded(after: trigger)
        sut.loadNextPageIfNeeded(after: trigger)
        await sut.pagingTask?.value

        #expect(await repository.requestedPages == [1, 2])
        #expect(sut.state.value?.count == 10)
    }

    @Test("A page asked for right after the previous one has to wait its turn")
    func brakesBetweenPagesAskedForBackToBack() async throws {
        // Sin el freno, un gesto rápido encadena varias páginas en menos de un segundo:
        // llega una, sus celdas aparecen con el dedo todavía en marcha y eso pide la
        // siguiente. Son cien personajes que nadie mira y una ráfaga que se gana el 429
        // de la API, que además se lleva por delante la carga que sí importaba.
        let waits = SleepRecorder()
        let repository = StubCharacterRepository(charactersByPage: [
            1: .success(.stub(page: 1, totalPages: 3, ids: 1...5)),
            2: .success(.stub(page: 2, totalPages: 3, ids: 6...10)),
        ])
        let sut = makeSUT(repository, recordingWaitsInto: waits)
        await sut.onAppear()

        try await scrollToTheEnd(of: sut)

        // Se ha esperado, y menos de lo que dura el freno entero: lo que se descuenta
        // es el tiempo que ya se fue en traer la página anterior
        let durations = await waits.durations
        #expect(durations.count == 1)
        #expect(durations.allSatisfy { $0 > .zero && $0 <= .milliseconds(400) })
        #expect(sut.state.value?.count == 10)
    }

    @Test("A page asked for long after the previous one goes straight through")
    func doesNotBrakeWhenTheUserTakesTheirTime() async throws {
        // El freno es contra la ráfaga, no contra el usuario: quien baja leyendo no
        // tiene por qué esperar nada.
        let waits = SleepRecorder()
        let repository = StubCharacterRepository(charactersByPage: [
            1: .success(.stub(page: 1, totalPages: 3, ids: 1...5)),
            2: .success(.stub(page: 2, totalPages: 3, ids: 6...10)),
        ])
        let sut = makeSUT(repository, recordingWaitsInto: waits)
        await sut.onAppear()
        try await Task.sleep(for: .milliseconds(450))

        try await scrollToTheEnd(of: sut)

        #expect(await waits.durations.isEmpty)
    }

    @Test("A cell that is not near the end does not ask for anything")
    func onlyTheLastCellsTrigger() async throws {
        let (sut, repository) = makeSUT(pages: [1: .success(.stub(page: 1, totalPages: 3, ids: 1...20))])
        await sut.onAppear()
        let first = try #require(sut.state.value?.first)

        sut.loadNextPageIfNeeded(after: first)
        await sut.pagingTask?.value

        #expect(await repository.requestedPages == [1])
    }

    @Test("Nothing is asked for past the last page")
    func stopsAtTheLastPage() async throws {
        let (sut, repository) = makeSUT(pages: [1: .success(.stub(page: 1, totalPages: 1, ids: 1...5))])
        await sut.onAppear()

        try await scrollToTheEnd(of: sut)

        #expect(await repository.requestedPages == [1])
        #expect(!sut.isLoadingNextPage)
    }

    // MARK: - Imágenes que adelantar

    @Test("The images to warm are the ones of the page that just arrived, not everything loaded")
    func publishesTheImagesOfTheLatestPage() async throws {
        // Lo que ya se ha visto ya está en disco; lo que hay que adelantar es lo que
        // viene. Publicar la lista entera haría que la vista volviera a recorrer
        // ochocientas URLs por cada página nueva.
        let (sut, _) = makeSUT(pages: [
            1: .success(.stub(page: 1, totalPages: 3, ids: 1...5)),
            2: .success(.stub(page: 2, totalPages: 3, ids: 6...10)),
        ])

        await sut.onAppear()
        #expect(sut.latestPageImageURLs.map(\.absoluteString) == (1...5).map(avatar))

        try await scrollToTheEnd(of: sut)
        #expect(sut.latestPageImageURLs.map(\.absoluteString) == (6...10).map(avatar))
    }

    @Test("A character without an image URL is left out of what is warmed")
    func leavesOutCharactersWithoutImage() async {
        let withoutImage = Character(
            id: 1,
            name: "No face",
            status: .unknown,
            species: "Human",
            type: nil,
            gender: .unknown,
            origin: "?",
            location: "?",
            imageURL: nil,
            episodeIDs: []
        )
        let page = Page(items: [withoutImage, .stub(id: 2)], currentPage: 1, totalPages: 1)
        let (sut, _) = makeSUT(pages: [1: .success(page)])

        await sut.onAppear()

        #expect(sut.latestPageImageURLs.map(\.absoluteString) == [avatar(2)])
    }

    private func avatar(_ id: Int) -> String {
        "https://rickandmortyapi.com/api/character/avatar/\(id).jpeg"
    }

    // MARK: - Fallos

    @Test("A first page that fails takes over the screen")
    func firstPageFailureReplacesTheScreen() async {
        let (sut, _) = makeSUT(pages: [1: .failure(.server(statusCode: 500))])

        await sut.onAppear()

        #expect(sut.state == .failed(.server(statusCode: 500)))
        #expect(sut.nextPageError == nil)
    }

    @Test("A next page that fails keeps the pages already on screen")
    func nextPageFailureKeepsWhatIsLoaded() async throws {
        // Es la diferencia entre un fallo de pantalla y un fallo de página: si se cae
        // la siguiente, las cinco que el usuario está mirando siguen siendo válidas.
        let (sut, _) = makeSUT(pages: [
            1: .success(.stub(page: 1, totalPages: 3, ids: 1...5)),
            2: .failure(.offline),
        ])
        await sut.onAppear()

        try await scrollToTheEnd(of: sut)

        #expect(sut.state.value?.map(\.id) == [1, 2, 3, 4, 5])
        #expect(sut.nextPageError == .offline)
        #expect(!sut.isLoadingNextPage)
    }

    @Test("A failed next page is not retried on its own while the user keeps scrolling")
    func aFailedNextPageDoesNotRetryItself() async throws {
        // Las celdas del final siguen apareciendo después del fallo. Sin la guarda,
        // cada aparición dispararía otra petición contra un servidor que ya ha dicho
        // que no.
        let (sut, repository) = makeSUT(pages: [
            1: .success(.stub(page: 1, totalPages: 3, ids: 1...5)),
            2: .failure(.offline),
        ])
        await sut.onAppear()
        try await scrollToTheEnd(of: sut)

        try await scrollToTheEnd(of: sut)

        #expect(await repository.requestedPages == [1, 2])
    }

    @Test("Retrying a failed next page asks for it again")
    func retryingANextPageAsksAgain() async throws {
        let (sut, repository) = makeSUT(pages: [
            1: .success(.stub(page: 1, totalPages: 3, ids: 1...5)),
            2: .failure(.offline),
        ])
        await sut.onAppear()
        try await scrollToTheEnd(of: sut)

        sut.retryNextPage()
        await sut.pagingTask?.value

        #expect(await repository.requestedPages == [1, 2, 2])
    }

    @Test("Retrying the first page asks for it again from the error screen")
    func retryingTheFirstPageAsksAgain() async {
        let (sut, repository) = makeSUT(pages: [1: .failure(.timeout)])
        await sut.onAppear()

        sut.retry()
        await sut.searchTask?.value

        #expect(await repository.requestedPages == [1, 1])
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
