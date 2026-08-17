import Foundation

// Una petición descrita como valor, que solo se resuelve contra la base al enviarla.
// Solo hay GET: la API es de solo lectura, y un método que nadie usa sería una promesa
// que nadie cumple —no habría cuerpo ni Content-Type que lo respaldaran.
// Montarlas con URLComponents y no interpolando strings es lo que hace que los valores
// se escapen solos: buscar "Rick & Morty" o un nombre con acentos generaría una URL
// mal formada sin enterarte.
struct Endpoint: Hashable, Sendable {
    // Siempre empieza por /, para que se pegue al path de la base
    let path: String
    var queryItems: [URLQueryItem] = []
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
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }
}
