import Foundation

struct RetryPolicy: Hashable, Sendable {
    // Intentos totales, contando el primero. Con 1 no se reintenta
    let maxAttempts: Int
    let baseDelay: Duration

    static let `default` = RetryPolicy(maxAttempts: 3, baseDelay: .milliseconds(300))
    static let none = RetryPolicy(maxAttempts: 1, baseDelay: .zero)

    // Backoff exponencial: 300 ms, 600 ms, 1,2 s...
    func delay(beforeAttempt attempt: Int) -> Duration {
        guard attempt > 1 else { return .zero }
        return baseDelay * Int(pow(2.0, Double(attempt - 2)))
    }
}

// Añade reintentos con backoff a cualquier HTTPClient.
// Es el principio abierto/cerrado en la práctica: el reintento es comportamiento
// nuevo que se añade componiendo, no un if metido dentro de URLSessionHTTPClient.
// Así los dos se entienden, y se testean, por separado.
struct RetryingHTTPClient: HTTPClient {
    private let wrapped: any HTTPClient
    private let policy: RetryPolicy
    private let sleep: @Sendable (Duration) async throws -> Void

    // sleep se inyecta para que los tests comprueben la secuencia de esperas sin
    // esperar de verdad. La suite se queda en milisegundos.
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
                    // Si sleep lanza es porque han cancelado. Respetarlo en vez de
                    // gastar los intentos que quedan.
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
