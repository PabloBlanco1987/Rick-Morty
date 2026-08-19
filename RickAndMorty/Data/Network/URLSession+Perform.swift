import Foundation

/// What a 2xx request returns: the bytes and how long the network took, not counting
/// the wait for the limiter's token. No raw response travels past this — status code
/// and Retry-After are already spent here, leaving only decoding or saving the bytes.
struct HTTPExchange: Sendable {
    let data: Data
    let duration: Duration
}

extension URLSession {
    /// A real request end to end: limiter token, logging, transport, status code, and
    /// reporting back to the limiter how it went. Shared by the app's only two network
    /// exits — URLSessionHTTPClient's JSON and ImageCache's images — living here so
    /// there's one copy instead of two that drift on what a 429 means. What each caller
    /// does with the bytes (decode a model, save to disk) is its own business.
    func perform(
        _ request: URLRequest,
        through limiter: RateLimiter
    ) async throws(AppError) -> HTTPExchange {
        let logger = NetworkLogger.shared

        // Before logging or starting the clock: waiting for a token isn't network time,
        // and the log should show only what the server took.
        try await limiter.acquire()

        logger.logRequest(request)
        let start = ContinuousClock.now

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await self.data(for: request)
        } catch let error as URLError {
            logger.logFailure(error, for: request, duration: start.duration(to: .now))
            throw AppError(error)
        } catch let error where error is CancellationError {
            logger.logFailure(error, for: request, duration: start.duration(to: .now))
            throw .cancelled
        } catch {
            logger.logFailure(error, for: request, duration: start.duration(to: .now))
            throw .unknown
        }

        let elapsed = start.duration(to: .now)

        guard let http = response as? HTTPURLResponse else {
            logger.logFailure(AppError.unknown, for: request, duration: elapsed)
            throw .unknown
        }

        // Logged before checking the status code, so a 404 or 429 shows up exactly as
        // it arrived, ahead of the AppError translation.
        logger.logResponse(http, for: request, duration: elapsed)

        // The limiter learns about it here, not in the AppError translation, because
        // Retry-After lives in the raw response and this is the only place that sees
        // it. issuedAt is what lets it tell a fresh 429 from one already in the brake.
        if http.statusCode == 429 {
            await limiter.reportRateLimited(retryAfter: http.retryAfter, issuedAt: start)
        } else if (200..<300).contains(http.statusCode) {
            await limiter.reportSuccess(issuedAt: start)
        }

        if let error = AppError(statusCode: http.statusCode) { throw error }
        return HTTPExchange(data: data, duration: elapsed)
    }
}
