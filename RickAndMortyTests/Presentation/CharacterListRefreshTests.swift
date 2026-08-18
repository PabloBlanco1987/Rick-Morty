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
    @Test("Refreshing replaces the list instead of appending to it")
    func refreshReplacesTheList() async throws {
        let (sut, repository) = CharacterListViewModel.forTesting(pages: [
            1: .success(.stub(page: 1, totalPages: 3, ids: 1...5)),
            2: .success(.stub(page: 2, totalPages: 3, ids: 6...10)),
        ])
        await sut.onAppear()
        try await sut.scrollToTheEnd()

        await sut.refresh()

        #expect(sut.state.value?.map(\.id) == [1, 2, 3, 4, 5])
        #expect(await repository.requestedPages == [1, 2, 1])
    }

    @Test("Only a refresh asks for fresh data; every other load settles for what is cached")
    func onlyARefreshAsksForFreshData() async throws {
        // La API sirve las páginas con noventa días de caducidad, así que sin decirlo la
        // primera página saldría de la caché de red igual que la primera vez y el gesto
        // no traería nada. Y al revés: si las demás cargas pidieran datos frescos, volver
        // del detalle o pasar página costarían una ida y vuelta que no hace falta.
        let (sut, repository) = CharacterListViewModel.forTesting(pages: [
            1: .success(.stub(page: 1, totalPages: 3, ids: 1...5)),
            2: .success(.stub(page: 2, totalPages: 3, ids: 6...10)),
        ])
        await sut.onAppear()
        try await sut.scrollToTheEnd()

        await sut.refresh()

        #expect(await repository.requestedFreshness == [.acceptCached, .acceptCached, .fresh])
    }

    @Test("While a refresh is in flight the list stays on screen, with no skeleton")
    func refreshKeepsTheListWhileLoading() async {
        // El propio control de refresco ya es el indicador; enseñar además los
        // esqueletos sería tapar la lista que el usuario tiene delante mientras tira de ella
        let gate = AsyncGate()
        let (sut, repository) = CharacterListViewModel.forTesting(pages: [
            1: .success(.stub(page: 1, totalPages: 3, ids: 1...5)),
        ])
        await sut.onAppear()

        await repository.holdListings(at: gate)
        let refreshing = Task { await sut.refresh() }
        await gate.waitUntilReached()

        #expect(sut.state.value?.map(\.id) == [1, 2, 3, 4, 5])

        await gate.open()
        await refreshing.value
    }

    @Test("A refresh that fails keeps the list the user was looking at, and says so")
    func refreshFailureKeepsTheList() async {
        // El refresh puede fallar; lo que no puede es dejar sin lista al que ya la
        // tenía delante. Una pantalla de error aquí sería castigar al usuario por
        // haber tirado hacia abajo. Pero una lista que se queda igual después de tirar
        // de ella parece fresca, así que el fallo se expone para que la vista avise.
        let (sut, repository) = CharacterListViewModel.forTesting(pages: [
            1: .success(.stub(page: 1, totalPages: 3, ids: 1...5)),
        ])
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
        let (sut, repository) = CharacterListViewModel.forTesting(pages: [
            1: .failure(.timeout),
        ])
        await sut.onAppear()

        await repository.setCharacters(.failure(.offline), forPage: 1)
        await sut.refresh()

        #expect(sut.state == .failed(.offline))
        #expect(sut.refreshFailure == nil)
    }

    @Test("Dismissing the refresh failure clears it and nothing else")
    func dismissingTheRefreshFailure() async {
        let (sut, repository) = CharacterListViewModel.forTesting(pages: [
            1: .success(.stub(page: 1, totalPages: 3, ids: 1...5)),
        ])
        await sut.onAppear()
        await repository.setCharacters(.failure(.offline), forPage: 1)
        await sut.refresh()

        sut.dismissRefreshFailure()

        #expect(sut.refreshFailure == nil)
        #expect(sut.state.value?.map(\.id) == [1, 2, 3, 4, 5])
    }

    @Test("A refresh that succeeds afterwards clears the failure: the list is fresh again")
    func aLaterSuccessfulRefreshClearsTheFailure() async {
        let (sut, repository) = CharacterListViewModel.forTesting(pages: [
            1: .success(.stub(page: 1, totalPages: 3, ids: 1...5)),
        ])
        await sut.onAppear()
        await repository.setCharacters(.failure(.offline), forPage: 1)
        await sut.refresh()

        await repository.setCharacters(.success(.stub(page: 1, totalPages: 3, ids: 1...5)), forPage: 1)
        await sut.refresh()

        #expect(sut.refreshFailure == nil)
    }

    @Test("Changing the criteria clears the failure: the list it warned about is gone")
    func aNewSearchClearsTheRefreshFailure() async {
        let (sut, repository) = CharacterListViewModel.forTesting(pages: [
            1: .success(.stub(page: 1, totalPages: 3, ids: 1...5)),
        ])
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
        let (sut, _) = CharacterListViewModel.forTesting(pages: [
            1: .success(.stub(page: 1, totalPages: 3, ids: 1...5)),
            2: .failure(.offline),
        ])
        await sut.onAppear()
        try await sut.scrollToTheEnd()

        await sut.refresh()

        #expect(sut.nextPageError == nil)
    }

    @Test("A refresh that fails because it was cancelled says nothing")
    func aCancelledRefreshIsNotAFailure() async {
        // Cancelar no es fallar: si el usuario se ha ido de la pantalla a mitad de gesto,
        // ni la lista cambia ni hay aviso del que enterarse
        let (sut, repository) = CharacterListViewModel.forTesting(pages: [
            1: .success(.stub(page: 1, totalPages: 3, ids: 1...5)),
        ])
        await sut.onAppear()

        await repository.setCharacters(.failure(.cancelled), forPage: 1)
        await sut.refresh()

        #expect(sut.state.value?.map(\.id) == [1, 2, 3, 4, 5])
        #expect(sut.refreshFailure == nil)
    }

    // MARK: - Carreras

    @Test("A refresh cancels the page that was loading, and that page is thrown away")
    func refreshCancelsThePageInFlight() async throws {
        // Un refresh sustituye la lista entera: una página que iba de camino para la
        // lista anterior no puede pegarse al final de la nueva. Y el indicador del pie se
        // apaga ya, no cuando esa página llegue.
        let gate = AsyncGate()
        let (sut, repository) = CharacterListViewModel.forTesting(pages: [
            1: .success(.stub(page: 1, totalPages: 3, ids: 1...5)),
            2: .success(.stub(page: 2, totalPages: 3, ids: 6...10)),
        ])
        await sut.onAppear()

        await repository.holdListings(at: gate)
        sut.loadNextPageIfNeeded(after: try #require(sut.state.value?.last))
        await gate.waitUntilReached()
        let stalePage = sut.pagingTask

        await repository.holdListings(at: nil)
        await sut.refresh()
        #expect(!sut.isLoadingNextPage)

        await gate.open()
        await stalePage?.value

        #expect(sut.state.value?.map(\.id) == [1, 2, 3, 4, 5])
        #expect(!sut.isLoadingNextPage)
        #expect(sut.nextPageError == nil)
    }

    @Test("A page asked for during a refresh does not land on the refreshed list")
    func aPageAskedForDuringARefreshIsDiscarded() async throws {
        // El refresh conserva la lista mientras trae la primera página, así que sus
        // celdas del final siguen en pantalla y pueden pedir la siguiente —la 3, si se
        // iba por la 2— antes de que llegue la 1 nueva. Sin la guarda, esa página
        // aterrizaba sobre la lista ya sustituida: página 1 seguida de la 3, con la 2
        // saltada para siempre.
        let gate = AsyncGate()
        let (sut, repository) = CharacterListViewModel.forTesting(pages: [
            1: .success(.stub(page: 1, totalPages: 3, ids: 1...5)),
            2: .success(.stub(page: 2, totalPages: 3, ids: 6...10)),
            3: .success(.stub(page: 3, totalPages: 3, ids: 11...15)),
        ])
        await sut.onAppear()
        try await sut.scrollToTheEnd()

        // El refresh queda congelado pidiendo la página 1, y mientras tanto una celda del
        // final pide la 3, que también se congela. Se abre para las dos, en el orden que
        // sea: la 3 no puede acabar debajo de la 1 en ninguno.
        await repository.holdListings(at: gate)
        let refreshing = Task { await sut.refresh() }
        await gate.waitUntilReached()
        sut.loadNextPageIfNeeded(after: try #require(sut.state.value?.last))
        let latePage = sut.pagingTask
        await gate.open()
        await refreshing.value
        await latePage?.value

        #expect(sut.state.value?.map(\.id) == [1, 2, 3, 4, 5])

        // Y la siguiente que se pida es la 2, no la 4: la paginación ha vuelto a empezar
        try await sut.scrollToTheEnd()
        #expect(await repository.requestedPages.last == 2)
    }

    @Test("A refresh that comes back after the criteria changed is discarded, even if it failed")
    func aLateRefreshForOlderCriteriaIsDiscarded() async {
        // El refresh no viaja en la tarea de búsqueda, así que cambiar el criterio no lo
        // cancela: es la comparación de filtros la que tiene que descartarlo. Y si además
        // falló, tampoco puede dejar el aviso de refresco sobre una lista que no es la
        // que refrescaba.
        let gate = AsyncGate()
        let (sut, repository) = CharacterListViewModel.forTesting(pages: [
            1: .success(.stub(page: 1, totalPages: 1, ids: 1...5)),
        ])
        await sut.onAppear()

        await repository.setCharacters(.failure(.offline), forPage: 1)
        await repository.holdListings(at: gate)
        let refreshing = Task { await sut.refresh() }
        await gate.waitUntilReached()

        await repository.holdListings(at: nil)
        await repository.setCharacters(.success(.stub(page: 1, totalPages: 1, ids: 100...102)), forPage: 1)
        sut.statusFilter = .dead
        await sut.searchTask?.value

        await gate.open()
        await refreshing.value

        #expect(sut.state.value?.map(\.id) == [100, 101, 102])
        #expect(sut.refreshFailure == nil)
    }

    @Test("A cancelled page that finishes late does not switch off the indicator of the page that replaced it")
    func aStalePageDoesNotClobberTheNewOne() async throws {
        // Un refresh cancela la página en vuelo y ya apaga el indicador. Si esa página
        // acabara más tarde y volviera a apagarlo, lo apagaría sobre la carga que la ha
        // sustituido: el pie se quedaría sin indicador y otra celda podría colar una
        // segunda petición de la misma página.
        let stale = AsyncGate()
        let fresh = AsyncGate()
        let (sut, repository) = CharacterListViewModel.forTesting(pages: [
            1: .success(.stub(page: 1, totalPages: 3, ids: 1...5)),
            2: .success(.stub(page: 2, totalPages: 3, ids: 6...10)),
        ])
        await sut.onAppear()

        // La página 2 de la lista vieja, congelada
        await repository.holdListings(at: stale)
        sut.loadNextPageIfNeeded(after: try #require(sut.state.value?.last))
        await stale.waitUntilReached()
        let stalePage = sut.pagingTask

        // El refresh la cancela y trae la 1; después se pide la 2 de la lista nueva, y esa
        // es la que se congela ahora
        await repository.holdListings(at: nil)
        await sut.refresh()
        await repository.holdListings(at: fresh)
        sut.loadNextPageIfNeeded(after: try #require(sut.state.value?.last))
        await fresh.waitUntilReached()
        let freshPage = sut.pagingTask
        #expect(sut.isLoadingNextPage)

        // La vieja termina tarde: no puede tocar el indicador de la nueva
        await stale.open()
        await stalePage?.value
        #expect(sut.isLoadingNextPage, "The stale page switched off the indicator of the page that replaced it")

        await fresh.open()
        await freshPage?.value
        #expect(sut.state.value?.map(\.id) == [1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
        #expect(!sut.isLoadingNextPage)
    }
}
