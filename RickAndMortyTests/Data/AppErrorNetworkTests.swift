import Foundation
import Testing
@testable import RickAndMorty

/// The table that translates what URLSession returns into `AppError`. Tested apart from
/// the HTTP client because two network paths share it — JSON and images — and what
/// matters is that the table is one and complete: the client's tests check it's used;
/// these test what it says.
@Suite("App error network translation")
struct AppErrorNetworkTests {
    @Test(
        "Anything that means 'no way to reach the server' is offline",
        arguments: [
            URLError.Code.notConnectedToInternet,
            .networkConnectionLost,
            .dataNotAllowed,
            .internationalRoamingOff,
            .cannotConnectToHost,
            .cannotFindHost,
            .dnsLookupFailed,
        ]
    )
    func connectivityFailuresAreOffline(code: URLError.Code) {
        // Same guidance in all seven cases — check the connection and retry — and
        // retrying alone won't fix any of them
        #expect(AppError(URLError(code)) == .offline)
    }

    @Test("A timeout and a cancellation keep their own case")
    func timeoutAndCancellationAreDistinct() {
        // Timeout retries on its own and cancellation is never shown to the user:
        // lumping both with "offline" would lose a distinct decision in each case
        #expect(AppError(URLError(.timedOut)) == .timeout)
        #expect(AppError(URLError(.cancelled)) == .cancelled)
    }

    @Test(
        "Everything else is unknown rather than guessed",
        arguments: [URLError.Code.badURL, .badServerResponse, .secureConnectionFailed, .httpTooManyRedirects]
    )
    func otherTransportFailuresAreUnknown(code: URLError.Code) {
        #expect(AppError(URLError(code)) == .unknown)
    }

    @Test("A 2xx has nothing to translate", arguments: [200, 201, 204, 299])
    func successCodesTranslateToNothing(statusCode: Int) {
        // nil, not a success case: the caller just proceeds with the bytes, and there's
        // no AppError.success someone could throw by mistake
        #expect(AppError(statusCode: statusCode) == nil)
    }

    @Test("404 and 429 are the two codes the app treats specially")
    func notFoundAndRateLimitedHaveTheirOwnCase() {
        // 404 is what the API returns for a search with no results, and 429 is what
        // Cloudflare returns on fast scrolling: both need their own reaction, not a
        // generic "server error" message
        #expect(AppError(statusCode: 404) == .notFound)
        #expect(AppError(statusCode: 429) == .rateLimited)
    }

    @Test("Any other status keeps its code", arguments: [400, 401, 403, 500, 502, 503])
    func otherStatusesKeepTheirCode(statusCode: Int) {
        // The code is kept because it decides whether a retry is worth it: yes for
        // 5xx, no for 4xx
        #expect(AppError(statusCode: statusCode) == .server(statusCode: statusCode))
    }
}
