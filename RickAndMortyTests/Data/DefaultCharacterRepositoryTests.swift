import Foundation
import Testing
@testable import RickAndMorty

@Suite("Default character repository")
struct DefaultCharacterRepositoryTests {
    private func makeSUT(_ outcome: StubHTTPClient.Outcome) -> DefaultCharacterRepository {
        DefaultCharacterRepository(remote: CharacterRemoteDataSource(client: StubHTTPClient([outcome])))
    }

    @Test("A listing is mapped into domain characters carrying the requested page")
    func mapsListing() async throws {
        // La API no dice qué página es, así que el número tiene que ser el que se pidió:
        // se pide la 3 para que un literal no pase por bueno
        let page = try await makeSUT(.json(JSONFixtures.charactersPage))
            .characters(page: 3, filter: .empty, freshness: .acceptCached)

        #expect(page.items.map(\.name) == ["Rick Sanchez", "Morty Smith"])
        #expect(page.currentPage == 3)
        #expect(page.totalPages == 42)
        #expect(page.hasNextPage)
    }

    @Test("A search that matches nothing is an empty result that remembers its page, not an error")
    func notFoundOnListingBecomesEmptyPage() async throws {
        // La API contesta a ?name=zzzz con un 404, no con un results vacío. Dejarlo
        // pasar como fallo sería enseñar una pantalla de error por una búsqueda
        // normal sin resultados, así que se traduce aquí. Y la página vacía se queda con
        // el número que se pidió: la 7, para que el valor por defecto de Page.empty() no
        // pase por bueno.
        let page = try await makeSUT(.failure(.notFound))
            .characters(page: 7, filter: CharacterFilter(name: "zzzz"), freshness: .acceptCached)

        #expect(page.items.isEmpty)
        #expect(page.currentPage == 7)
        #expect(!page.hasNextPage)
    }

    @Test("Real failures on a listing are not swallowed by the 404 translation")
    func otherListingErrorsPropagate() async {
        let sut = makeSUT(.failure(.server(statusCode: 500)))

        await #expect(throws: AppError.server(statusCode: 500)) {
            _ = try await sut.characters(page: 1, filter: .empty, freshness: .acceptCached)
        }
    }

    @Test("A missing character stays a genuine notFound on the detail path")
    func notFoundOnDetailStaysAnError() async {
        // Mismo código, significado contrario: nadie ha buscado el personaje 9999,
        // se ha navegado a él, así que aquí "no hay nada" sí es un error de verdad
        let sut = makeSUT(.failure(.notFound))

        await #expect(throws: AppError.notFound) {
            _ = try await sut.character(id: 9_999)
        }
    }

    @Test("A detail payload is mapped into a domain character")
    func mapsDetail() async throws {
        let character = try await makeSUT(.json(JSONFixtures.rick)).character(id: 1)

        #expect(character.name == "Rick Sanchez")
        #expect(character.status == .alive)
        #expect(character.episodeIDs == [1, 2])
    }

    @Test("Episodes are mapped, air dates included")
    func mapsEpisodes() async throws {
        let episodes = try await makeSUT(.json(JSONFixtures.episodeArray)).episodes(ids: [1, 2])

        #expect(episodes.map(\.code) == ["S01E01", "S01E02"])
        #expect(episodes.allSatisfy { $0.airDate != nil })
    }

    @Test("The freshness the caller asks for reaches the request")
    func forwardsTheFreshness() async throws {
        // El repositorio está entre el dominio, que dice "fresco", y el data source, que
        // lo traduce a HTTP. Si no lo pasara, el refresco quedaría en un gesto sin efecto.
        let stub = StubHTTPClient(json: JSONFixtures.charactersPage)
        let sut = DefaultCharacterRepository(remote: CharacterRemoteDataSource(client: stub))

        _ = try await sut.characters(page: 1, filter: .empty, freshness: .acceptCached)
        _ = try await sut.characters(page: 1, filter: .empty, freshness: .fresh)

        let policies = await stub.requestedEndpoints.map(\.cachePolicy)
        #expect(policies == [.useProtocolCachePolicy, .reloadRevalidatingCacheData])
    }
}
