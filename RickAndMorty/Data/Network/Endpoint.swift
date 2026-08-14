import Foundation

enum HTTPMethod: String, Hashable, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
}

/// A request described as a value, resolved against a base URL only when it is sent.
///
/// Building requests with `URLComponents` rather than string interpolation is what
/// makes query values percent-encode themselves — a search for `Rick & Morty` or an
/// accented name would silently produce a malformed URL otherwise.
struct Endpoint: Hashable, Sendable {
    let path: String
    var queryItems: [URLQueryItem] = []
    var method: HTTPMethod = .get

    func urlRequest(baseURL: URL) -> URLRequest? {
        guard var components = URLComponents(
            url: baseURL.appending(path: path),
            resolvingAgainstBaseURL: false
        ) else { return nil }

        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }

        guard let url = components.url else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }
}
