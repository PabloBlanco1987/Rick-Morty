import Foundation

/// The catalog of endpoints the app uses. Keeping every path and parameter name in one
/// file means the API's vocabulary appears exactly once. CharacterFilter is a domain
/// type; translating it to `?status=alive&gender=female` is Data's job, done here.
enum RickAndMortyAPI {
    // The base built field by field, not parsed from a string — URLComponents can't
    // fail to construct, so no literal here needs trusting on faith.
    static let base: URLComponents = {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "rickandmortyapi.com"
        components.path = "/api"
        return components
    }()

    static func characters(
        page: Int,
        filter: CharacterFilter = .empty,
        freshness: Freshness = .acceptCached
    ) -> Endpoint {
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

        // Where "fresh" becomes HTTP. Pages carry a 90-day expiry, so under the normal
        // policy a seen page loads from URLSession's cache untouched; revalidating
        // sends the saved ETag and expects a bodyless 304 if nothing changed — a light
        // round trip instead of another download.
        let cachePolicy: URLRequest.CachePolicy = switch freshness {
        case .acceptCached: .useProtocolCachePolicy
        case .fresh: .reloadRevalidatingCacheData
        }

        return Endpoint(path: "/character", queryItems: items, cachePolicy: cachePolicy)
    }

    static func character(id: Int) -> Endpoint {
        Endpoint(path: "/character/\(id)")
    }

    // Batch endpoint: one request for all of a character's episodes instead of one
    // per episode. Hides a shape change — /episode/1,2 answers with an array,
    // /episode/1 with a bare object — that CharacterRemoteDataSource absorbs.
    static func episodes(ids: [Int]) -> Endpoint {
        Endpoint(path: "/episode/\(ids.map(String.init).joined(separator: ","))")
    }
}
