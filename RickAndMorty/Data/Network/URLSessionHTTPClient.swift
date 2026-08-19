import Foundation

/// Where all of the app's JSON goes out to the network — the other is `ImageCache`'s
/// image download, which fetches bytes instead of models. The two share failure
/// translation, logging, and rate limiting. Everything that can fail here becomes an
/// `AppError`, so `URLError` and `DecodingError` never escape the data layer.
struct URLSessionHTTPClient: HTTPClient {
    private let base: URLComponents
    private let session: URLSession
    private let limiter: RateLimiter
    private let logger = NetworkLogger.shared

    init(
        base: URLComponents = RickAndMortyAPI.base,
        session: URLSession = .rickAndMorty,
        // Same limiter the image cache uses — one server quota for JSON and images,
        // so they share the brake.
        limiter: RateLimiter = .shared
    ) {
        self.base = base
        self.session = session
        self.limiter = limiter
    }

    func send<Response: Decodable & Sendable>(
        _ endpoint: Endpoint,
        as type: Response.Type
    ) async throws(AppError) -> Response {
        guard let request = endpoint.urlRequest(base: base) else {
            throw .unknown
        }

        // Rate limiting, logging, transport, and status codes live in
        // URLSession.perform, shared with image downloads. What's left here is
        // JSON-specific: turning bytes into a model.
        let exchange = try await session.perform(request, through: limiter)

        do {
            return try JSONDecoder.rickAndMorty.decode(Response.self, from: exchange.data)
        } catch {
            logger.logFailure(error, for: request, duration: exchange.duration)
            throw .decoding
        }
    }
}

extension URLSession {
    // The session the app runs on. This private URLCache is the whole response cache:
    // the API sends ETag and a 90-day Cache-Control, so a seen page loads from disk
    // under .useProtocolCachePolicy — free to revisit — and only revalidates with a
    // 304 when the endpoint asks for it, which is what pull-to-refresh does via
    // Freshness.
    static let rickAndMorty: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = URLCache(
            memoryCapacity: 20 * 1024 * 1024,
            diskCapacity: 100 * 1024 * 1024
        )
        configuration.requestCachePolicy = .useProtocolCachePolicy
        configuration.timeoutIntervalForRequest = 15
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()
}

extension JSONDecoder {
    // The API is all snake_case
    static let rickAndMorty: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()
}
