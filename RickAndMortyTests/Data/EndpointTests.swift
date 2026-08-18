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

    @Test("Requests ask for JSON")
    func requestShape() throws {
        // El método no se comprueba: Endpoint no lo pone, y URLRequest ya es GET por
        // defecto, que es el único que usa una API de solo lectura
        let request = try #require(RickAndMortyAPI.character(id: 1).urlRequest(base: base))
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
    }

    @Test("Typed criteria travel trimmed: the server never sees the surrounding spaces")
    func sendsTrimmedValues() throws {
        // La barra de búsqueda de iOS reescribe el texto con espacios al perder el foco.
        // Si viajaran, "rick " y "rick" serían dos entradas distintas en la caché de
        // URLSession para la misma búsqueda.
        let filter = CharacterFilter(name: "  rick ", species: " Human\n")
        let url = try url(RickAndMortyAPI.characters(page: 1, filter: filter))
        let query = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)

        #expect(query.contains(URLQueryItem(name: "name", value: "rick")))
        #expect(query.contains(URLQueryItem(name: "species", value: "Human")))
    }

    @Test("A refresh revalidates; every other load takes what the cache has, at the same URL")
    func freshnessBecomesACachePolicy() throws {
        // La API sirve las páginas con noventa días de caducidad: con la política normal
        // una página ya vista sale de la caché sin tocar la red. El pull to refresh es la
        // única carga que tiene que preguntar al servidor, y lo hace con una condicional
        // sobre la misma URL, no con otra petición: si la URL cambiara, no habría ETag
        // guardado que mandar.
        let cached = RickAndMortyAPI.characters(page: 1, freshness: .acceptCached)
        let fresh = RickAndMortyAPI.characters(page: 1, freshness: .fresh)

        #expect(cached.cachePolicy == .useProtocolCachePolicy)
        #expect(fresh.cachePolicy == .reloadRevalidatingCacheData)
        #expect(try url(cached) == url(fresh))
    }

    @Test("The cache policy travels with the request, not just with the endpoint")
    func cachePolicyReachesTheRequest() throws {
        // La sesión tiene una política por defecto; la de la petición manda sobre ella.
        // Es lo que permite que la misma sesión sirva de caché al navegar y revalide al
        // refrescar.
        let request = try #require(RickAndMortyAPI.characters(page: 1, freshness: .fresh).urlRequest(base: base))
        #expect(request.cachePolicy == .reloadRevalidatingCacheData)
    }
}
