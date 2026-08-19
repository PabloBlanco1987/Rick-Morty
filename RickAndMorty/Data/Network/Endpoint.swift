import Foundation

/// A request described as a value, resolved against the base only when sent. GET only —
/// the API is read-only. Built with `URLComponents`, not string interpolation, so query
/// values escape themselves: searching "Rick & Morty" won't silently produce a bad URL.
struct Endpoint: Hashable, Sendable {
    let path: String
    var queryItems: [URLQueryItem] = []
    var cachePolicy: URLRequest.CachePolicy = .useProtocolCachePolicy

    func urlRequest(base: URLComponents) -> URLRequest? {
        var components = base
        components.path += path

        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }

        guard let url = components.url else { return nil }

        var request = URLRequest(url: url, cachePolicy: cachePolicy)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }
}
