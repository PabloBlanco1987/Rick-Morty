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
        // Built by string interpolation, any of these cases would have ended up as a
        // malformed request
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

    @Test("Requests ask for JSON")
    func requestShape() throws {
        // The method isn't checked: Endpoint doesn't set one, and URLRequest already
        // defaults to GET — the only one a read-only API uses
        let request = try #require(RickAndMortyAPI.character(id: 1).urlRequest(base: base))
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
    }

    @Test("Typed criteria travel trimmed: the server never sees the surrounding spaces")
    func sendsTrimmedValues() throws {
        // iOS's search bar leaves trailing spaces when it loses focus. If they
        // traveled, "rick " and "rick" would be two different URLSession cache entries
        // for the same search.
        let filter = CharacterFilter(name: "  rick ", species: " Human\n")
        let url = try url(RickAndMortyAPI.characters(page: 1, filter: filter))
        let query = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)

        #expect(query.contains(URLQueryItem(name: "name", value: "rick")))
        #expect(query.contains(URLQueryItem(name: "species", value: "Human")))
    }

    @Test("A refresh revalidates; every other load takes what the cache has, at the same URL")
    func freshnessBecomesACachePolicy() throws {
        // The API serves pages with a ninety-day expiry: under the normal policy, a
        // page already seen comes straight from cache without touching the network.
        // Pull-to-refresh is the only load that must ask the server, and it does so
        // with a conditional request on the same URL, not a different one — if the URL
        // changed, there'd be no stored ETag to send.
        let cached = RickAndMortyAPI.characters(page: 1, freshness: .acceptCached)
        let fresh = RickAndMortyAPI.characters(page: 1, freshness: .fresh)

        #expect(cached.cachePolicy == .useProtocolCachePolicy)
        #expect(fresh.cachePolicy == .reloadRevalidatingCacheData)
        #expect(try url(cached) == url(fresh))
    }

    @Test("The cache policy travels with the request, not just with the endpoint")
    func cachePolicyReachesTheRequest() throws {
        // The session has a default policy; the request's overrides it. That's what
        // lets the same session serve as cache while browsing and revalidate on
        // refresh.
        let request = try #require(RickAndMortyAPI.characters(page: 1, freshness: .fresh).urlRequest(base: base))
        #expect(request.cachePolicy == .reloadRevalidatingCacheData)
    }
}
