import Foundation

struct RetryPolicy: Hashable, Sendable {
    /// Total attempts, including the first one. `1` disables retrying.
    let maxAttempts: Int
    let baseDelay: Duration

    static let `default` = RetryPolicy(maxAttempts: 3, baseDelay: .milliseconds(300))
    static let none = RetryPolicy(maxAttempts: 1, baseDelay: .zero)

    /// Exponential backoff: 300 ms, 600 ms, 1.2 s…
    func delay(beforeAttempt attempt: Int) -> Duration {
        guard attempt > 1 else { return .zero }
        return baseDelay * Int(pow(2.0, Double(attempt - 2)))
    }
}

/// Adds retry-with-backoff to any `HTTPClient`.
///
/// This is the open/closed principle made concrete: retrying is new behaviour added
/// by composition, not an `if` branch grafted into `URLSessionHTTPClient`. The two
/// can be reasoned about, and tested, apart.
struct RetryingHTTPClient: HTTPClient {
    private let wrapped: any HTTPClient
    private let policy: RetryPolicy
    private let sleep: @Sendable (Duration) async throws -> Void

    /// - Parameter sleep: injected so tests exercise the backoff sequence without
    ///   actually waiting. The suite stays in the millisecond range.
    init(
        wrapping wrapped: any HTTPClient,
        policy: RetryPolicy = .default,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.wrapped = wrapped
        self.policy = policy
        self.sleep = sleep
    }

    func send<Response: Decodable & Sendable>(
        _ endpoint: Endpoint,
        as type: Response.Type
    ) async throws(AppError) -> Response {
        var lastError: AppError = .unknown

        for attempt in 1...max(1, policy.maxAttempts) {
            if attempt > 1 {
                do {
                    try await sleep(policy.delay(beforeAttempt: attempt))
                } catch {
                    // The only way `sleep` throws is cancellation; honour it rather
                    // than burning through the remaining attempts.
                    throw .cancelled
                }
            }

            do {
                return try await wrapped.send(endpoint, as: type)
            } catch {
                guard error.isRetryable else { throw error }
                lastError = error
            }
        }

        throw lastError
    }
}
