import Foundation

struct RetryPolicy: Hashable, Sendable {
    let maxAttempts: Int
    let baseDelay: Duration
    // What to wait after a rate limit — an order of magnitude more, because the
    // problem isn't a failure, it's asking for too much: retrying at 300ms just
    // extends the penalty.
    let rateLimitedDelay: Duration

    static let `default` = RetryPolicy(
        maxAttempts: 3,
        baseDelay: .milliseconds(300),
        // 2s, then 4s. Any less and all three attempts burn inside the same window
        // the server is still saying no in, and the user sees an error for something
        // a bit more patience would have fixed.
        rateLimitedDelay: .seconds(2)
    )
    static let none = RetryPolicy(maxAttempts: 1, baseDelay: .zero, rateLimitedDelay: .zero)

    // Exponential backoff on whichever base applies: 300ms, 600ms, 1.2s… or 2s, 4s,
    // 8s if the server said to slow down.
    func delay(beforeAttempt attempt: Int, after error: AppError) -> Duration {
        guard attempt > 1 else { return .zero }
        let base = switch error.retryPatience {
        case .brief: baseDelay
        case .backOff: rateLimitedDelay
        }
        return base * Int(pow(2.0, Double(attempt - 2)))
    }

    // The retry loop, written once for everyone who retries — the HTTP client and the
    // image download share it instead of each keeping a copy. What differs between
    // them comes in as a parameter, including sleep, which tests swap for a recorder.
    func attempt<Value: Sendable>(
        sleep: @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        shouldRetry: (AppError) -> Bool = \.isRetryable,
        _ operation: () async throws(AppError) -> Value
    ) async throws(AppError) -> Value {
        var lastError: AppError = .unknown

        for attempt in 1...max(1, maxAttempts) {
            if attempt > 1 {
                do {
                    try await sleep(delay(beforeAttempt: attempt, after: lastError))
                } catch {
                    throw .cancelled
                }
            }

            do {
                return try await operation()
            } catch {
                guard shouldRetry(error) else { throw error }
                lastError = error
            }
        }

        throw lastError
    }
}

/// Adds backoff retries to any `HTTPClient`. Open/closed in practice: retrying is new
/// behavior added by composing, not an `if` inside `URLSessionHTTPClient` — so each is
/// understood, and tested, on its own.
struct RetryingHTTPClient: HTTPClient {
    private let wrapped: any HTTPClient
    private let policy: RetryPolicy
    private let sleep: @Sendable (Duration) async throws -> Void

    // sleep is injected so tests check the sequence of waits without waiting for real.
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
        // The closure's full signature is spelled out because typed-throws inference
        // inside a literal falls back to `any Error`.
        try await policy.attempt(sleep: sleep) { () async throws(AppError) -> Response in
            try await wrapped.send(endpoint, as: type)
        }
    }
}
