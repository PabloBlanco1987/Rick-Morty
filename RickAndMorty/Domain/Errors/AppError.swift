import Foundation

/// The only error type that crosses a layer boundary.
///
/// `URLError`, `DecodingError` and HTTP status codes are all translated into this
/// closed set inside the Data layer, so neither the domain nor the view models ever
/// have to know what a status code is. Presentation turns each case into copy.
enum AppError: Error, Equatable, Sendable {
    /// The device has no usable connection.
    case offline
    /// The request outlived its timeout.
    case timeout
    /// The resource genuinely does not exist.
    case notFound
    /// The server answered, but not with a success status.
    case server(statusCode: Int)
    /// The payload arrived but did not match the expected shape.
    case decoding
    /// The caller cancelled — usually a superseded search. Never shown to the user.
    case cancelled
    case unknown

    /// Whether an automatic retry stands a reasonable chance of succeeding.
    ///
    /// Connectivity loss is excluded on purpose: retrying 300 ms after the radio
    /// dropped almost never helps, and it is better UX to surface a Retry button
    /// immediately than to spin for a second first.
    var isRetryable: Bool {
        switch self {
        case .timeout:
            true
        case .server(let statusCode):
            (500..<600).contains(statusCode)
        case .offline, .notFound, .decoding, .cancelled, .unknown:
            false
        }
    }
}
