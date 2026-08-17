import Foundation
import Testing
@testable import RickAndMorty

// El pull to refresh tiene su propia suite porque su regla es distinta a la de las
// demás cargas: sustituye la lista en vez de añadirle, y si falla no puede llevársela
// por delante. Lo que se prueba aquí es esa regla y lo que se expone para que la vista
// avise de que lo que se ve puede estar viejo.
@MainActor
@Suite("Character list refresh")
struct CharacterListRefreshTests {
    private func makeSUT(pages: [Int: Result<Page<Character>, AppError>]) -> (
        CharacterListViewModel, StubCharacterRepository
    ) {
        let repository = StubCharacterRepository(charactersByPage: pages)
        let sut = CharacterListViewModel(
            fetchCharacters: FetchCharactersUseCase(repository: repository),
            sleep: { _ in }
        )
        return (sut, repository)
    }

    @Test("Refreshing replaces the list instead of appending to it")
    func refreshReplacesTheList() async throws {
        let (sut, repository) = makeSUT(pages: [
            1: .success(.stub(page: 1, totalPages: 3, ids: 1...5)),
            2: .success(.stub(page: 2, totalPages: 3, ids: 6...10)),
        ])
        await sut.onAppear()
        try await scrollToTheEnd(of: sut)

        await sut.refresh()

        #expect(sut.state.value?.map(\.id) == [1, 2, 3, 4, 5])
        #expect(await repository.requestedPages == [1, 2, 1])
    }

    @Test("A refresh that fails keeps the list the user was looking at, and says so")
    func refreshFailureKeepsTheList() async {
        // El refresh puede fallar; lo que no puede es dejar sin lista al que ya la
        // tenía delante. Una pantalla de error aquí sería castigar al usuario por
        // haber tirado hacia abajo. Pero una lista que se queda igual después de tirar
        // de ella parece fresca, así que el fallo se expone para que la vista avise.
        let (sut, repository) = makeSUT(pages: [1: .success(.stub(page: 1, totalPages: 3, ids: 1...5))])
        await sut.onAppear()

        await repository.setCharacters(.failure(.offline), forPage: 1)
        await sut.refresh()

        #expect(sut.state.value?.map(\.id) == [1, 2, 3, 4, 5])
        #expect(sut.refreshFailure == .offline)
    }

    @Test("A refresh that fails with nothing on screen is a screen failure, not a notice")
    func refreshFailureWithoutAListOwnsTheScreen() async {
        // Sin lista que conservar no hay nada de lo que avisar: el error es la pantalla,
        // igual que en la primera carga
        let (sut, repository) = makeSUT(pages: [1: .failure(.timeout)])
        await sut.onAppear()

        await repository.setCharacters(.failure(.offline), forPage: 1)
        await sut.refresh()

        #expect(sut.state == .failed(.offline))
        #expect(sut.refreshFailure == nil)
    }

    @Test("Dismissing the refresh failure clears it and nothing else")
    func dismissingTheRefreshFailure() async {
        let (sut, repository) = makeSUT(pages: [1: .success(.stub(page: 1, totalPages: 3, ids: 1...5))])
        await sut.onAppear()
        await repository.setCharacters(.failure(.offline), forPage: 1)
        await sut.refresh()

        sut.dismissRefreshFailure()

        #expect(sut.refreshFailure == nil)
        #expect(sut.state.value?.map(\.id) == [1, 2, 3, 4, 5])
    }

    @Test("A refresh that succeeds afterwards clears the failure: the list is fresh again")
    func aLaterSuccessfulRefreshClearsTheFailure() async {
        let (sut, repository) = makeSUT(pages: [1: .success(.stub(page: 1, totalPages: 3, ids: 1...5))])
        await sut.onAppear()
        await repository.setCharacters(.failure(.offline), forPage: 1)
        await sut.refresh()

        await repository.setCharacters(.success(.stub(page: 1, totalPages: 3, ids: 1...5)), forPage: 1)
        await sut.refresh()

        #expect(sut.refreshFailure == nil)
    }

    @Test("Changing the criteria clears the failure: the list it warned about is gone")
    func aNewSearchClearsTheRefreshFailure() async {
        let (sut, repository) = makeSUT(pages: [1: .success(.stub(page: 1, totalPages: 3, ids: 1...5))])
        await sut.onAppear()
        await repository.setCharacters(.failure(.offline), forPage: 1)
        await sut.refresh()

        await repository.setCharacters(.success(.stub(page: 1, totalPages: 1, ids: 1...2)), forPage: 1)
        sut.statusFilter = .dead
        await sut.searchTask?.value

        #expect(sut.refreshFailure == nil)
    }

    @Test("Refreshing clears a previous next page error")
    func refreshClearsTheNextPageError() async throws {
        let (sut, _) = makeSUT(pages: [
            1: .success(.stub(page: 1, totalPages: 3, ids: 1...5)),
            2: .failure(.offline),
        ])
        await sut.onAppear()
        try await scrollToTheEnd(of: sut)

        await sut.refresh()

        #expect(sut.nextPageError == nil)
    }

    // Simula que aparece la última celda cargada y espera a lo que eso dispare
    private func scrollToTheEnd(of sut: CharacterListViewModel) async throws {
        let last = try #require(sut.state.value?.last)
        sut.loadNextPageIfNeeded(after: last)
        await sut.pagingTask?.value
    }
}
