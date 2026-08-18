import Foundation
import Testing
@testable import RickAndMorty

@Suite("Character remote data source")
struct CharacterRemoteDataSourceTests {
    @Test("Asking for no episodes costs no request at all")
    func noEpisodesMeansNoRequest() async throws {
        let stub = StubHTTPClient(json: JSONFixtures.episodeArray)
        let sut = CharacterRemoteDataSource(client: stub)

        let episodes = try await sut.episodes(ids: [])

        #expect(episodes.isEmpty)
        await #expect(stub.callCount == 0)
    }

    @Test("A single id answers with a bare object and still comes back as an array")
    func singleEpisodeIsWrapped() async throws {
        // El endpoint cambia de forma según cuántos ids pidas, y este es el caso que
        // rompe sin avisar si decodificas directamente a [EpisodeDTO].self
        let stub = StubHTTPClient(json: JSONFixtures.singleEpisode)
        let sut = CharacterRemoteDataSource(client: stub)

        let episodes = try await sut.episodes(ids: [1])

        #expect(episodes.count == 1)
        #expect(episodes.first?.name == "Pilot")
    }

    @Test("Several ids are fetched as one batched array response")
    func multipleEpisodesDecodeAsArray() async throws {
        let stub = StubHTTPClient(json: JSONFixtures.episodeArray)
        let sut = CharacterRemoteDataSource(client: stub)

        let episodes = try await sut.episodes(ids: [1, 2])

        #expect(episodes.map(\.id) == [1, 2])
        await #expect(stub.callCount == 1)
        await #expect(stub.requestedEndpoints.first?.path == "/episode/1,2")
    }

    @Test("A listing forwards the page and filter to the endpoint")
    func listingBuildsTheRightEndpoint() async throws {
        let stub = StubHTTPClient(json: JSONFixtures.charactersPage)
        let sut = CharacterRemoteDataSource(client: stub)

        _ = try await sut.characters(page: 4, filter: CharacterFilter(status: .alive))

        let endpoint = try #require(await stub.requestedEndpoints.first)
        #expect(endpoint.path == "/character")
        #expect(endpoint.queryItems.contains(URLQueryItem(name: "page", value: "4")))
        #expect(endpoint.queryItems.contains(URLQueryItem(name: "status", value: "alive")))
    }

    @Test("The detail addresses one character by id")
    func detailBuildsTheRightEndpoint() async throws {
        let stub = StubHTTPClient(json: JSONFixtures.rick)
        let sut = CharacterRemoteDataSource(client: stub)

        let dto = try await sut.character(id: 42)

        #expect(dto.name == "Rick Sanchez")
        await #expect(stub.requestedEndpoints.first?.path == "/character/42")
    }

    @Test("A fresh listing asks for an endpoint that revalidates")
    func freshListingRevalidates() async throws {
        // El data source es quien traduce la frescura del dominio a la política de caché
        // de la petición: si se perdiera aquí, el pull to refresh saldría de la caché
        let stub = StubHTTPClient(json: JSONFixtures.charactersPage)
        let sut = CharacterRemoteDataSource(client: stub)

        _ = try await sut.characters(page: 1, filter: .empty, freshness: .fresh)

        await #expect(stub.requestedEndpoints.first?.cachePolicy == .reloadRevalidatingCacheData)
    }
}
