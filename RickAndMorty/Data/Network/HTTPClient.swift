import Foundation

/// Sends an `Endpoint` and decodes the response. Knows nothing about characters or
/// episodes, which is exactly what lets it be decorated (`RetryingHTTPClient`) and
/// swapped out in tests without touching the network.
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
