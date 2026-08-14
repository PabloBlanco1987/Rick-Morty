import Foundation

/// The one place in the app that talks to the network.
///
/// Every failure mode — transport, status code, malformed payload — is translated
/// into `AppError` before it leaves this type, so `URLError` and `DecodingError`
/// never escape the Data layer.
struct URLSessionHTTPClient: HTTPClient {
    private let baseURL: URL
    private let session: URLSession

    init(baseURL: URL = RickAndMortyAPI.baseURL, session: URLSession = .rickAndMorty) {
        self.baseURL = baseURL
        self.session = session
    }

    func send<Response: Decodable & Sendable>(
        _ endpoint: Endpoint,
        as type: Response.Type
    ) async throws(AppError) -> Response {
        guard let request = endpoint.urlRequest(baseURL: baseURL) else {
            throw .unknown
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw Self.appError(for: error)
        } catch is CancellationError {
            throw .cancelled
        } catch {
            throw .unknown
        }

        guard let http = response as? HTTPURLResponse else { throw .unknown }

        switch http.statusCode {
        case 200..<300:
            break
        case 404:
            throw .notFound
        default:
            throw .server(statusCode: http.statusCode)
        }

        do {
            // A `JSONDecoder` is not `Sendable`, so it is built per call rather than
            // stored. Allocating one costs microseconds against a request measured in
            // tens of milliseconds — not a trade worth an `@unchecked Sendable`.
            return try JSONDecoder.rickAndMorty.decode(Response.self, from: data)
        } catch {
            throw .decoding
        }
    }

    private static func appError(for error: URLError) -> AppError {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed,
             .internationalRoamingOff, .cannotConnectToHost, .cannotFindHost:
            .offline
        case .timedOut:
            .timeout
        case .cancelled:
            .cancelled
        default:
            .unknown
        }
    }
}

extension URLSession {
    /// The session the app ships with.
    ///
    /// The private `URLCache` is the whole of the response-caching story: the API
    /// serves `ETag` and `Cache-Control`, and `.useProtocolCachePolicy` means a page
    /// already seen is revalidated with a conditional request — a 304 with no body —
    /// or served straight from disk. No hand-rolled cache layer needed.
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
    /// The API is uniformly snake_case (`air_date`, `created`), so one strategy
    /// replaces a `CodingKeys` enum in every DTO.
    static var rickAndMorty: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}
