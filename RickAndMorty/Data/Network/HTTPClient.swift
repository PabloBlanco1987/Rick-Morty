import Foundation

/// Sends an `Endpoint` and decodes the response.
///
/// The client knows nothing about characters or episodes — that single
/// responsibility is what lets it be decorated (`RetryingHTTPClient`) and stubbed in
/// tests without any of them touching the network.
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
