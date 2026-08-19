import Foundation
import OSLog

/// Debug network trace: logs what's requested, what the server answers, and how long
/// it took — one line per request and one per response, no body dump. Lives here and
/// not in a decorator like `RetryingHTTPClient` because a decorator only sees the
/// `Endpoint` going in and the decoded model coming out, never the status code. Compiles
/// out entirely in release: bodies are DEBUG-only, so release calls are no-ops.
struct NetworkLogger: Sendable {
    // One shared trace for the app: named directly by callers, not injected. The
    // exception to that rule on purpose — tests turn it off by environment, so an
    // injection nobody would use is a fake seam.
    static let shared = NetworkLogger()

    // Off during tests: the suite fires plenty of fake requests, and the log would
    // bury what's actually being looked at.
    private let isEnabled = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil

    private init() {}

    // MARK: - Entry points

    // URLs log with privacy: .public on purpose, search text included — this is a
    // DEBUG-only trace against a public API, and redacting the query would hide the
    // one thing worth seeing: what's being asked for.
    func logRequest(_ request: URLRequest) {
        #if DEBUG
        guard isEnabled else { return }
        Self.log.debug("📤 Request \(summary(of: request), privacy: .public)")
        #endif
    }

    func logResponse(_ response: HTTPURLResponse, for request: URLRequest, duration: Duration) {
        #if DEBUG
        guard isEnabled else { return }
        let line = "📥 Response \(response.statusCode) \(summary(of: request)) · \(formatted(duration))"
        // A 2xx is background noise; a 404 or 500 is what you're looking for — different
        // log levels so the console filter can tell them apart.
        if (200..<300).contains(response.statusCode) {
            Self.log.debug("\(line, privacy: .public)")
        } else {
            Self.log.error("\(line, privacy: .public)")
        }
        #endif
    }

    // Works the same for a transport failure or a payload that won't decode: either
    // way, this is the last place to see the real error before it becomes an AppError.
    func logFailure(_ error: some Error, for request: URLRequest, duration: Duration) {
        #if DEBUG
        guard isEnabled else { return }
        let line = "❌ Response \(summary(of: request)) · \(formatted(duration)) · \(String(describing: error))"
        Self.log.error("\(line, privacy: .public)")
        #endif
    }

    // What the rate limiter decides: when it brakes and at what rate it recovers. Logs
    // at .notice, not .debug — it's what to check when the grid goes gray.
    // @autoclosure so the interpolated text is only built when it's actually logged;
    // in release the body compiles empty, so formatting it would be wasted work.
    func logThrottle(_ message: @autoclosure () -> String) {
        #if DEBUG
        guard isEnabled else { return }
        let text = message()
        Self.log.notice("\(text, privacy: .public)")
        #endif
    }

    // MARK: - Formatting

    #if DEBUG
    private static let log = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "RickAndMorty",
        category: "Network"
    )

    private func summary(of request: URLRequest) -> String {
        "\(request.httpMethod ?? "GET") \(request.url?.absoluteString ?? "-")"
    }

    private func formatted(_ duration: Duration) -> String {
        let milliseconds = Double(duration.components.seconds) * 1_000
            + Double(duration.components.attoseconds) * 1e-15
        return String(format: "%.0f ms", milliseconds)
    }
    #endif
}
