import Foundation

// Manda un Endpoint y decodifica la respuesta.
// No sabe nada de personajes ni de episodios, y justo por eso se puede decorar
// (RetryingHTTPClient) y sustituir en tests sin tocar la red.
protocol HTTPClient: Sendable {
    func send<Response: Decodable & Sendable>(
        _ endpoint: Endpoint,
        as type: Response.Type
    ) async throws(AppError) -> Response
}

extension HTTPClient {
    func send<Response: Decodable & Sendable>(_ endpoint: Endpoint) async throws(AppError) -> Response {
        try await send(endpoint, as: Response.self)
    }
}
