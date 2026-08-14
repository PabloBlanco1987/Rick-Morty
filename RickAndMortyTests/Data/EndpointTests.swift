import Foundation
import Testing
@testable import RickAndMorty

@Suite("Endpoint and API catalogue")
struct EndpointTests {
    private let base = RickAndMortyAPI.base

    private func url(_ endpoint: Endpoint) throws -> URL {
        try #require(endpoint.urlRequest(base: base)?.url)
    }

    @Test("An unfiltered listing asks only for a page")
    func plainListing() throws {
        let url = try url(RickAndMortyAPI.characters(page: 2))
        #expect(url.absoluteString == "https://rickandmortyapi.com/api/character?page=2")
    }

    @Test("Every active criterion becomes a query parameter")
    func filteredListing() throws {
        let filter = CharacterFilter(name: "rick", status: .alive, gender: .male, species: "Human")
        let url = try url(RickAndMortyAPI.characters(page: 1, filter: filter))

        let query = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(query.count == 5)
        #expect(query.contains(URLQueryItem(name: "page", value: "1")))
        #expect(query.contains(URLQueryItem(name: "name", value: "rick")))
        #expect(query.contains(URLQueryItem(name: "status", value: "alive")))
        #expect(query.contains(URLQueryItem(name: "gender", value: "male")))
        #expect(query.contains(URLQueryItem(name: "species", value: "Human")))
    }

    @Test("Inactive criteria are left out rather than sent empty")
    func omitsEmptyCriteria() throws {
        let filter = CharacterFilter(name: "  ", status: nil, gender: nil, species: "")
        let url = try url(RickAndMortyAPI.characters(page: 1, filter: filter))
        #expect(url.absoluteString == "https://rickandmortyapi.com/api/character?page=1")
    }

    @Test("Reserved characters in a search term are percent-encoded")
    func encodesSearchTerm() throws {
        // Montando la URL a base de interpolar strings, cualquiera de estos casos
        // habría acabado en una petición mal formada
        let url = try url(RickAndMortyAPI.characters(page: 1, filter: CharacterFilter(name: "rick & morty")))
        let query = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)

        #expect(query.contains(URLQueryItem(name: "name", value: "rick & morty")))
        #expect(!url.absoluteString.contains("rick & morty"))
        #expect(url.absoluteString.contains("%26"))
    }

    @Test("Episodes are fetched in one batched request, not one per id")
    func batchesEpisodes() throws {
        let url = try url(RickAndMortyAPI.episodes(ids: [1, 2, 51]))
        #expect(url.absoluteString == "https://rickandmortyapi.com/api/episode/1,2,51")
    }

    @Test("A detail request addresses a single character")
    func characterDetail() throws {
        let url = try url(RickAndMortyAPI.character(id: 42))
        #expect(url.absoluteString == "https://rickandmortyapi.com/api/character/42")
    }

    @Test("Requests declare the method and accept JSON")
    func requestShape() throws {
        let request = try #require(RickAndMortyAPI.character(id: 1).urlRequest(base: base))
        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
    }
}
