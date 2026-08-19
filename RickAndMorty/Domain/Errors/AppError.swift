import Foundation

/// The only error that crosses a layer boundary. Data translates `URLError`,
/// `DecodingError`, and HTTP status codes into these cases; Presentation turns each
/// into its text.
enum AppError: Error, Equatable, Sendable {
    case offline
    case timeout
    case notFound
    case rateLimited
    // Server responded, but not with a 2xx.
    case server(statusCode: Int)
    // Payload arrived but doesn't match the expected shape.
    case decoding
    case cancelled
    case unknown

    // Whether a retry is worth it. Offline is excluded on purpose: retrying 300ms after
    // losing coverage rarely works, and showing the retry button beats a spinner.
    var isRetryable: Bool {
        switch self {
        case .timeout:
            true
        // The textbook "try again, but later" case. Handling it here is what keeps a
        // fast scroll from ending in an error screen — it just quietly retries.
        case .rateLimited:
            true
        case .server(let statusCode):
            (500..<600).contains(statusCode)
        case .offline, .notFound, .decoding, .cancelled, .unknown:
            false
        }
    }

    // How long to wait before retrying. A 500 is usually a millisecond hiccup;
    // rate-limiting isn't fixed by insisting right away — that only extends it.
    // Exhaustive on purpose, like isRetryable: a new case must decide its own patience.
    var retryPatience: RetryPatience {
        switch self {
        case .rateLimited: .backOff
        case .offline, .timeout, .notFound, .server, .decoding, .cancelled, .unknown: .brief
        }
    }

    enum RetryPatience: Sendable {
        case brief
        case backOff
    }
}
