import Foundation

/// The catalogue of endpoints this app uses.
///
/// Confining every path and query-parameter name to one file means the API's
/// vocabulary appears exactly once. `CharacterFilter` is a domain type; translating
/// it into `?status=alive&gender=female` is a Data-layer concern and belongs here.
enum RickAndMortyAPI {
    static let baseURL = URL(string: "https://rickandmortyapi.com/api")!

    static func characters(page: Int, filter: CharacterFilter = .none) -> Endpoint {
        var items = [URLQueryItem(name: "page", value: String(page))]

        if !filter.trimmedName.isEmpty {
            items.append(URLQueryItem(name: "name", value: filter.trimmedName))
        }
        if let status = filter.status {
            items.append(URLQueryItem(name: "status", value: status.rawValue))
        }
        if let gender = filter.gender {
            items.append(URLQueryItem(name: "gender", value: gender.rawValue))
        }
        if !filter.trimmedSpecies.isEmpty {
            items.append(URLQueryItem(name: "species", value: filter.trimmedSpecies))
        }

        return Endpoint(path: "/character", queryItems: items)
    }

    static func character(id: Int) -> Endpoint {
        Endpoint(path: "/character/\(id)")
    }

    /// The batch endpoint: one request for every episode a character appears in,
    /// instead of one request per episode.
    ///
    /// Note the shape change it hides — `/episode/1,2` answers with an array while
    /// `/episode/1` answers with a single object. `CharacterRemoteDataSource` is where
    /// that quirk is absorbed.
    static func episodes(ids: [Int]) -> Endpoint {
        Endpoint(path: "/episode/\(ids.map(String.init).joined(separator: ","))")
    }
}
