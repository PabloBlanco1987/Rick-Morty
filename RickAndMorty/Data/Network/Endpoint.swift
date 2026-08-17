import Foundation

enum HTTPMethod: String, Hashable, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
}

// Una petición descrita como valor, que solo se resuelve contra la base al enviarla.
// Montarlas con URLComponents y no interpolando strings es lo que hace que los valores
// se escapen solos: buscar "Rick & Morty" o un nombre con acentos generaría una URL
// mal formada sin enterarte.
struct Endpoint: Hashable, Sendable {
    // Siempre empieza por /, para que se pegue al path de la base
    let path: String
    var queryItems: [URLQueryItem] = []
    var method: HTTPMethod = .get
    // Por petición y no solo en la sesión: la misma URL se pide con la política normal al
    // navegar y revalidando cuando el usuario refresca, y la sesión no puede saber cuál
    // de las dos es
    var cachePolicy: URLRequest.CachePolicy = .useProtocolCachePolicy

    func urlRequest(base: URLComponents) -> URLRequest? {
        var components = base
        components.path += path

        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }

        guard let url = components.url else { return nil }

        var request = URLRequest(url: url, cachePolicy: cachePolicy)
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }
}
