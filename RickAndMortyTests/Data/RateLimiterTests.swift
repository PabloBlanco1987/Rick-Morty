import Foundation
import Testing
@testable import RickAndMorty

/// The limiter is what decides when a request reaches the network, so what's under test
/// is its decisions: how long to hold, how fast it resumes, and what it does with what
/// the server says. Where a real clock matters — that a token wait actually happens — the
/// margins are sized so a slow machine can only widen them, never break them.
@Suite("Rate limiter")
struct RateLimiterTests {
    // MARK: - The shared brake

    @Test("A rate limited response puts every request on hold, not just its own")
    func aRateLimitHoldsEveryone() async throws {
        // This is what separates recovering from sinking further: if each image
        // retried its own 429, the retry would repeat the burst that triggered the
        // limit and never escape it. The brake is shared because the limit is
        // shared: two requests unrelated to the one that got the 429 both wait.
        let sut = RateLimiter(coolOff: .milliseconds(80))
        let clock = ContinuousClock()

        await sut.reportRateLimited(retryAfter: nil)
        async let first = clock.measure { try await sut.acquire() }
        async let second = clock.measure { try await sut.acquire() }
        let (firstWait, secondWait) = try await (first, second)

        #expect(firstWait >= .milliseconds(70))
        #expect(secondWait >= .milliseconds(70))
    }

    @Test("The hold lifts on its own: the next request waits it out and goes through")
    func theHoldLiftsOnItsOwn() async throws {
        // What's measured is that the wait exists; that it ends, that acquire()
        // returns. That a success clears the streak is proven by aSuccessResetsTheEscalation.
        let sut = RateLimiter(coolOff: .milliseconds(50))
        await sut.reportRateLimited(retryAfter: nil)

        let waited = try await ContinuousClock().measure { try await sut.acquire() }

        #expect(waited >= .milliseconds(40))
        #expect(await sut.isCoolingOff == false)
    }

    @Test("Each consecutive 429 doubles the hold, up to eight times the base")
    func consecutiveRateLimitsDoubleTheHold() async {
        // If the server keeps saying no, insisting at the same rate just extends
        // the punishment. And there's a cap: without one, a bad streak would leave
        // the app silent for minutes.
        let sut = RateLimiter(coolOff: .seconds(10))

        await sut.reportRateLimited(retryAfter: nil)
        let first = await sut.remainingCoolOff
        await sut.reportRateLimited(retryAfter: nil)
        let second = await sut.remainingCoolOff
        for _ in 0..<5 { await sut.reportRateLimited(retryAfter: nil) }
        let capped = await sut.remainingCoolOff

        #expect(first.isAbout(.seconds(10)))
        #expect(second.isAbout(.seconds(20)))
        #expect(capped.isAbout(.seconds(80)))
    }

    @Test("A success in between resets the escalation")
    func aSuccessResetsTheEscalation() async {
        let sut = RateLimiter(coolOff: .seconds(10))

        await sut.reportRateLimited(retryAfter: nil)
        await sut.reportSuccess()
        await sut.reportRateLimited(retryAfter: nil)

        #expect(await sut.remainingCoolOff.isAbout(.seconds(10)))
    }

    @Test("When the server says how long to wait, that is what is waited")
    func honoursRetryAfter() async {
        // Cloudflare knows better than we do how much punishment is left. With a
        // ten-second base, a one-second wait can only come from the header.
        let sut = RateLimiter(coolOff: .seconds(10))

        await sut.reportRateLimited(retryAfter: .seconds(1))

        #expect(await sut.remainingCoolOff.isAbout(.seconds(1)))
    }

    @Test("A Retry-After beyond reason is capped")
    func capsRetryAfter() async {
        // An outlandish header can't leave the app silent for half a minute for no
        // reason but a number
        let sut = RateLimiter()

        await sut.reportRateLimited(retryAfter: .seconds(600))

        #expect(await sut.remainingCoolOff.isAbout(.seconds(30)))
    }

    @Test("Waiting out the hold can be cancelled")
    func cancellingWhileHeldThrowsCancelled() async {
        let sut = RateLimiter(coolOff: .seconds(60))
        await sut.reportRateLimited(retryAfter: nil)

        let waiting = Task { try await sut.acquire() }
        waiting.cancel()

        await #expect(throws: AppError.cancelled) { try await waiting.value }
    }

    // MARK: - What happened before the brake doesn't count

    @Test("A 429 from a request that was already in flight when the hold started does not escalate it")
    func aRateLimitFromBeforeTheHoldDoesNotCount() async {
        // When Cloudflare cuts off, the four image slots and the in-flight page
        // all answer 429 almost at once. Counted one by one, a single server
        // warning would leave the brake at eight times the base and the rate on
        // the floor. Everything that went out before the brake was set belongs to
        // the same burst: the first one sets it and the rest add nothing.
        let sut = RateLimiter(maxRate: 8, coolOff: .seconds(10))
        let issuedBeforeTheHold = ContinuousClock.now

        await sut.reportRateLimited(retryAfter: nil)
        await sut.reportRateLimited(retryAfter: nil, issuedAt: issuedBeforeTheHold)
        await sut.reportRateLimited(retryAfter: nil, issuedAt: issuedBeforeTheHold)

        #expect(await sut.remainingCoolOff.isAbout(.seconds(10)))
        #expect(await sut.currentRate == 4)
    }

    @Test("A success from before the hold says nothing about now: it neither resets the count nor recovers rate")
    func aSuccessFromBeforeTheHoldDoesNotCount() async {
        // A request that went out before the brake and came back fine says how
        // the server was doing before it said no, not how it's doing now. If it
        // cleared the streak, the next 429 would fall back to the base wait and
        // the brake would never escalate.
        let sut = RateLimiter(maxRate: 8, coolOff: .seconds(10), recoveryStreak: 1)
        let issuedBeforeTheHold = ContinuousClock.now

        await sut.reportRateLimited(retryAfter: nil)
        await sut.reportSuccess(issuedAt: issuedBeforeTheHold)
        #expect(await sut.currentRate == 4)

        await sut.reportRateLimited(retryAfter: nil)

        // If the old success had counted, this would be the first 429 of a new
        // streak and the wait would fall back to the base; that the escalation
        // continues proves it didn't count. The opposite case — a later success
        // does recover rate — is already covered by adaptsTheRate.
        #expect(await sut.remainingCoolOff.isAbout(.seconds(20)))
    }

    // MARK: - The adaptive rate

    @Test("A 429 halves the rate, down to a floor; successes bring it back one step at a time")
    func adaptsTheRate() async {
        // Halves on the way down, climbs one step at a time: it's cheaper to err
        // slow than to earn the brake again. And the floor keeps a bad streak from
        // dropping the rate to zero, which would mean never requesting again.
        let sut = RateLimiter(maxRate: 8, minRate: 2, coolOff: .zero, recoveryStreak: 3)

        await sut.reportRateLimited(retryAfter: nil)
        #expect(await sut.currentRate == 4)
        await sut.reportRateLimited(retryAfter: nil)
        #expect(await sut.currentRate == 2)
        await sut.reportRateLimited(retryAfter: nil)
        #expect(await sut.currentRate == 2)

        for _ in 0..<3 { await sut.reportSuccess() }
        #expect(await sut.currentRate == 3)
        for _ in 0..<2 { await sut.reportSuccess() }
        #expect(await sut.currentRate == 3)
        await sut.reportSuccess()
        #expect(await sut.currentRate == 4)
    }

    @Test("A 429 wipes a recovery streak in progress: the climb starts over")
    func aRateLimitResetsThePartialStreak() async {
        // Two successes out of three aren't earned rate until the third arrives,
        // and a 429 in between wipes them: if they counted, the first success
        // afterward would raise the rate right when the server just asked for the
        // opposite
        let sut = RateLimiter(maxRate: 8, minRate: 2, coolOff: .zero, recoveryStreak: 3)
        await sut.reportRateLimited(retryAfter: nil)
        for _ in 0..<2 { await sut.reportSuccess() }

        await sut.reportRateLimited(retryAfter: nil)
        await sut.reportSuccess()

        #expect(await sut.currentRate == 2)
        for _ in 0..<2 { await sut.reportSuccess() }
        #expect(await sut.currentRate == 3)
    }

    @Test("The rate never climbs past the maximum")
    func doesNotExceedTheMaximum() async {
        let sut = RateLimiter(maxRate: 8, recoveryStreak: 1)

        for _ in 0..<10 { await sut.reportSuccess() }

        #expect(await sut.currentRate == 8)
    }

    // MARK: - The token bucket

    @Test("Requests within the burst go straight through; the next one waits for a token")
    func spacesRequestsBeyondTheBurst() async throws {
        // Ten tokens per second with a burst of three: the first three go out
        // right away and the fourth waits for one to be generated, about a hundred
        // milliseconds. That's the difference between limiting how many go at once
        // and limiting how many go out per second, which is what the server counts.
        let sut = RateLimiter(maxRate: 10, burst: 3)
        let clock = ContinuousClock()

        let burst = try await clock.measure {
            for _ in 0..<3 { try await sut.acquire() }
        }
        let fourth = try await clock.measure {
            try await sut.acquire()
        }

        // A slow machine can only make the fourth one longer, and even the
        // slowest doesn't take half a second for three calls that wait on nothing
        #expect(burst < .milliseconds(500))
        #expect(fourth >= .milliseconds(80))
    }

    @Test("A 429 empties the bucket and keeps it empty through the hold, so nothing bursts out when it lifts")
    func theBucketStaysEmptyThroughTheHold() async throws {
        // Neither the leftover burst survives, nor does another build up while
        // the brake holds: if the bucket refilled meanwhile, lifting the brake
        // would release a whole burst at once — exactly what the server just said
        // it doesn't want.
        // With the rate already halved — ten per second — and the bucket empty,
        // three requests in a row cost the brake plus three hundred-millisecond
        // tokens: half a second. If the bucket refilled during the brake, two of
        // the three would go out right as it lifted and the total wouldn't exceed
        // 300 ms.
        let sut = RateLimiter(maxRate: 20, burst: 3, coolOff: .milliseconds(200))
        let clock = ContinuousClock()

        await sut.reportRateLimited(retryAfter: nil)
        let elapsed = try await clock.measure {
            for _ in 0..<3 { try await sut.acquire() }
        }

        // A slow machine can only lengthen the wait, never shorten it
        #expect(elapsed >= .milliseconds(450))
    }

    @Test("Waiting for a token can be cancelled too")
    func cancellingWhileWaitingForATokenThrowsCancelled() async throws {
        // This is the other place acquire() sleeps. A cell that leaves while
        // waiting for a token can't stay parked until its turn, nor go out to the
        // network when its turn comes: whoever was waiting no longer wants to go.
        let sut = RateLimiter(maxRate: 1, burst: 1)
        try await sut.acquire()

        let waiting = Task { try await sut.acquire() }
        waiting.cancel()

        await #expect(throws: AppError.cancelled) { try await waiting.value }
    }

    @Test("The disabled limiter never waits and never holds, whatever the server says")
    func disabledDoesNothing() async throws {
        // This is what the HTTP client tests and previews use: a 429 with
        // Retry-After can't leave the brake engaged for the next one
        let sut = RateLimiter.disabled
        let clock = ContinuousClock()

        let elapsed = try await clock.measure {
            for _ in 0..<50 { try await sut.acquire() }
        }
        await sut.reportRateLimited(retryAfter: .seconds(30))

        #expect(elapsed < .milliseconds(500))
        #expect(await sut.isCoolingOff == false)
    }
}

@Suite("Retry-After header")
struct RetryAfterHeaderTests {
    @Test("Seconds are read as a duration", arguments: [("7", Duration.seconds(7)), (" 12 ", .seconds(12))])
    func readsSeconds(raw: String, expected: Duration) throws {
        #expect(try response(retryAfter: raw).retryAfter == expected)
    }

    @Test(
        "Missing, zero or a date give nothing to wait for",
        arguments: [nil, "0", "-3", "Wed, 21 Oct 2015 07:28:00 GMT"]
    )
    func ignoresWhatIsNotAPositiveNumber(raw: String?) throws {
        // The date form is ignored on purpose: Cloudflare doesn't use it and
        // parsing it would be more code than it's worth. With no value, the
        // limiter falls back to its own wait.
        #expect(try response(retryAfter: raw).retryAfter == nil)
    }

    private func response(retryAfter: String?) throws -> HTTPURLResponse {
        try #require(HTTPURLResponse(
            url: URL(filePath: "/api/character"),
            statusCode: 429,
            httpVersion: "HTTP/1.1",
            headerFields: retryAfter.map { ["Retry-After": $0] }
        ))
    }
}

private extension Optional where Wrapped == Duration {
    // What's left of a brake just set: the target minus however many microseconds
    // the check took to run. A one-second margin is plenty on any machine and
    // still tells ten apart from twenty.
    func isAbout(_ target: Duration) -> Bool {
        guard let self else { return false }
        return self > target - .seconds(1) && self <= target
    }
}
