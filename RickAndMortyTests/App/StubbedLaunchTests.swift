import Foundation
import Testing
@testable import RickAndMorty

// El repositorio en memoria con el que arrancan los tests de interfaz. Es código del
// target de la app —vive dentro de #if DEBUG— y de él dependen esos tests: si paginara o
// filtrara distinto que el servidor, un test de interfaz se pondría rojo o verde por el
// motivo equivocado. Aquí se comprueba que se porta como lo que suplanta.
@Suite("Stubbed launch repository")
struct StubbedLaunchTests {
    private let sut = StubbedCharacterRepository()

    @Test("Pages like the server: twenty per page, and an empty page past the end")
    func pagesLikeTheServer() async throws {
        let first = try await sut.characters(page: 1, filter: .empty, freshness: .acceptCached)
        let second = try await sut.characters(page: 2, filter: .empty, freshness: .acceptCached)
        let beyond = try await sut.characters(page: 3, filter: .empty, freshness: .acceptCached)

        #expect(first.items.count == 20)
        #expect(first.hasNextPage)
        #expect(second.items.map(\.id) == [21, 22, 23, 24, 25])
        #expect(!second.hasNextPage)
        #expect(beyond.items.isEmpty)
        #expect(beyond.currentPage == 3)
    }

    @Test("Filters combine like the server's: partial match, case-insensitive, all at once")
    func filtersCombineLikeTheServer() async throws {
        // Los mismos criterios que aplica la API, para que un test de interfaz que
        // filtre vea lo mismo que vería contra el servidor
        let filter = CharacterFilter(name: "smith", status: .alive, gender: .female, species: "HUMAN")

        let page = try await sut.characters(page: 1, filter: filter, freshness: .acceptCached)

        #expect(page.items.map(\.name) == ["Summer Smith", "Beth Smith"])
        #expect(page.totalPages == 1)
    }

    @Test("A filter that matches nothing is an empty page, like the repository's 404 translation")
    func noMatchesIsAnEmptyPage() async throws {
        let page = try await sut.characters(page: 1, filter: CharacterFilter(name: "zzzz"), freshness: .acceptCached)

        #expect(page.items.isEmpty)
        #expect(!page.hasNextPage)
    }

    @Test("Refreshing fails only when asked to, and only for the loads that demand fresh data")
    func refreshFailsOnlyWhenAsked() async throws {
        // Es la única forma de que un test de interfaz vea el aviso de refresco fallido
        // sin depender de que no haya red: las cargas normales siguen contestando
        let failing = StubbedCharacterRepository(refreshFails: true)

        _ = try await failing.characters(page: 1, filter: .empty, freshness: .acceptCached)
        _ = try await sut.characters(page: 1, filter: .empty, freshness: .fresh)
        await #expect(throws: AppError.offline) {
            _ = try await failing.characters(page: 1, filter: .empty, freshness: .fresh)
        }
    }

    @Test("The detail answers with the same character the list showed, and its episodes")
    func detailMatchesTheList() async throws {
        let listed = try await sut.characters(page: 1, filter: .empty, freshness: .acceptCached).items[0]

        let character = try await sut.character(id: listed.id)
        let episodes = try await sut.episodes(ids: character.episodeIDs)

        #expect(character == listed)
        #expect(episodes.map(\.id) == character.episodeIDs)
        await #expect(throws: AppError.notFound) { _ = try await sut.character(id: 999) }
    }
}
