import Foundation
import Testing
@testable import RickAndMorty

/// Serialized because `StubURLProtocol` holds process-level state: the `URLProtocol`
/// registration is global, so two of these running at once would answer each other's
/// requests.
@Suite("URLSession HTTP client", .serialized)
struct URLSessionHTTPClientTests {
    private let sut = URLSessionHTTPClient(
        base: RickAndMortyAPI.base,
        session: StubURLProtocol.makeSession(),
        // No limiter: this tests response translation, not pacing, and the 429
        // test can't leave the process's .shared brake engaged
        limiter: .disabled
    )

    @Test("Decodes a success payload into the requested type")
    func decodesSuccess() async throws {
        StubURLProtocol.install(.ok(JSONFixtures.rick))

        let dto = try await sut.send(RickAndMortyAPI.character(id: 1), as: CharacterDTO.self)

        #expect(dto.id == 1)
        #expect(dto.name == "Rick Sanchez")
    }

    @Test("Sends the URL the endpoint described")
    func sendsTheBuiltURL() async throws {
        StubURLProtocol.install(.ok(JSONFixtures.charactersPage))

        _ = try await sut.send(
            RickAndMortyAPI.characters(page: 2, filter: CharacterFilter(status: .dead)),
            as: PageDTO<CharacterDTO>.self
        )

        let sent = try #require(StubURLProtocol.lastRequest?.url?.absoluteString)
        #expect(sent.contains("/character"))
        #expect(sent.contains("page=2"))
        #expect(sent.contains("status=dead"))
    }

    @Test("A refresh reaches the session asking to revalidate what it has cached")
    func aFreshListingRevalidates() async throws {
        // The last link in freshness: the policy travels in the request, not the
        // session, since the same session caches while browsing and revalidates on
        // refresh. This checks it reaches what actually goes out.
        StubURLProtocol.install(.ok(JSONFixtures.charactersPage))

        _ = try await sut.send(RickAndMortyAPI.characters(page: 1, freshness: .fresh), as: PageDTO<CharacterDTO>.self)

        #expect(StubURLProtocol.lastRequest?.cachePolicy == .reloadRevalidatingCacheData)
    }

    @Test("Translates 404 into notFound, keeping the status code out of the domain")
    func mapsNotFound() async {
        StubURLProtocol.install(.status(404, json: JSONFixtures.notFoundError))

        await #expect(throws: AppError.notFound) {
            _ = try await sut.send(RickAndMortyAPI.character(id: 9_999), as: CharacterDTO.self)
        }
    }

    @Test("Carries the status code through for other failures", arguments: [500, 502, 400])
    func mapsServerErrors(statusCode: Int) async {
        StubURLProtocol.install(.status(statusCode))

        await #expect(throws: AppError.server(statusCode: statusCode)) {
            _ = try await sut.send(RickAndMortyAPI.character(id: 1), as: CharacterDTO.self)
        }
    }

    @Test("A 429 is rate limiting, not a server error")
    func mapsRateLimiting() async {
        // The API sits behind Cloudflare and answers this as soon as several pages
        // are requested in a row, which is what fast scrolling does. Filing it under
        // .server excluded it from retries and showed an error screen for something
        // that fixes itself by waiting.
        StubURLProtocol.install(.status(429, json: #"{ "title": "Error 1015: You are being rate limited" }"#))

        await #expect(throws: AppError.rateLimited) {
            _ = try await sut.send(RickAndMortyAPI.character(id: 1), as: CharacterDTO.self)
        }
    }

    @Test("A 429 tells the shared limiter to hold, for as long as the server says")
    func reportsRateLimitingToTheLimiter() async throws {
        // This is what makes a 429 on the JSON also brake image loads, and vice
        // versa: the brake is shared, and Retry-After is read by whoever has the raw
        // response in front of them — this client.
        let limiter = RateLimiter(coolOff: .seconds(10))
        let sut = URLSessionHTTPClient(
            base: RickAndMortyAPI.base,
            session: StubURLProtocol.makeSession(),
            limiter: limiter
        )
        var stub = StubURLProtocol.Stub.status(429)
        stub.headers["Retry-After"] = "3"
        StubURLProtocol.install(stub)

        _ = try? await sut.send(RickAndMortyAPI.character(id: 1), as: CharacterDTO.self)

        // Bounded on both sides: not the ten-second base — that would mean the
        // header was ignored — and nothing much below three, which would mean
        // misreading it
        let remaining = try #require(await limiter.remainingCoolOff)
        #expect(remaining > .seconds(2))
        #expect(remaining <= .seconds(3))
        #expect(await limiter.currentRate == 4)
    }

    @Test("A success tells the limiter, which is how the rate recovers")
    func reportsSuccessToTheLimiter() async throws {
        // High rate so the token to wait for after the 429 — the bucket empties —
        // costs microseconds, not a real quarter-second of wall clock
        let limiter = RateLimiter(maxRate: 1_000, coolOff: .zero, recoveryStreak: 1)
        let sut = URLSessionHTTPClient(
            base: RickAndMortyAPI.base,
            session: StubURLProtocol.makeSession(),
            limiter: limiter
        )
        await limiter.reportRateLimited(retryAfter: nil)
        StubURLProtocol.install(.ok(JSONFixtures.rick))

        _ = try await sut.send(RickAndMortyAPI.character(id: 1), as: CharacterDTO.self)

        #expect(await limiter.currentRate == 501)
    }

    @Test("A failure that is not a 429 leaves the limiter alone: it says nothing about the pace")
    func otherFailuresDoNotTouchTheLimiter() async throws {
        // A 500 is a server stumble, not a sign of going too fast: it neither
        // brakes nor lowers the rate, and it doesn't count as a success toward
        // recovering it either
        let limiter = RateLimiter(maxRate: 1_000, coolOff: .zero, recoveryStreak: 1)
        let sut = URLSessionHTTPClient(
            base: RickAndMortyAPI.base,
            session: StubURLProtocol.makeSession(),
            limiter: limiter
        )
        await limiter.reportRateLimited(retryAfter: nil)
        StubURLProtocol.install(.status(500))

        _ = try? await sut.send(RickAndMortyAPI.character(id: 1), as: CharacterDTO.self)

        #expect(await limiter.currentRate == 500)
        #expect(await limiter.isCoolingOff == false)
    }

    @Test("A payload of the wrong shape is a decoding failure, not a crash")
    func mapsDecodingFailure() async {
        StubURLProtocol.install(.ok(#"{ "unexpected": true }"#))

        await #expect(throws: AppError.decoding) {
            _ = try await sut.send(RickAndMortyAPI.character(id: 1), as: CharacterDTO.self)
        }
    }

    @Test("Connectivity failures surface as offline", arguments: [
        URLError.Code.notConnectedToInternet,
        .networkConnectionLost,
        .dataNotAllowed,
        .cannotFindHost,
    ])
    func mapsOffline(code: URLError.Code) async {
        StubURLProtocol.install(.transport(code))

        await #expect(throws: AppError.offline) {
            _ = try await sut.send(RickAndMortyAPI.character(id: 1), as: CharacterDTO.self)
        }
    }

    @Test("A timeout is distinguishable from being offline")
    func mapsTimeout() async {
        StubURLProtocol.install(.transport(.timedOut))

        await #expect(throws: AppError.timeout) {
            _ = try await sut.send(RickAndMortyAPI.character(id: 1), as: CharacterDTO.self)
        }
    }

    @Test("Cancellation is its own case, never shown as an error to the user")
    func mapsCancellation() async {
        StubURLProtocol.install(.transport(.cancelled))

        await #expect(throws: AppError.cancelled) {
            _ = try await sut.send(RickAndMortyAPI.character(id: 1), as: CharacterDTO.self)
        }
    }
}
