import Foundation

/// The rate at which the app allows itself onto the network, for the whole host at once.
/// Cloudflare limits by IP ahead of its own cache, so JSON pages and avatars share one
/// quota — and it's Cloudflare issuing the 429, not the API. Two mechanisms:
/// - A token bucket: `rate` tokens/second up to `burst`, one spent per request, waits
///   when empty. Turns "react to the penalty" into "don't earn it."
/// - A shared brake on a 429: nobody goes out until `Retry-After` passes (or a doubling
///   backoff if the server doesn't say), the rate is halved, and it recovers gradually
///   on a streak of successes — congestion control, since Cloudflare's real threshold
///   isn't documented.
///
/// An actor because image downloads and the HTTP client touch it at once, and the state
/// it guards — tokens, brake, rate — has to be one shared thing for the brake to hold.
actor RateLimiter {
    static let shared = RateLimiter()

    // No rate, no brake — for tests that test something else and shouldn't wait on
    // anyone. A computed property on purpose: each access is a fresh instance, so one
    // test's 429 doesn't leave the brake set for the next.
    static var disabled: RateLimiter {
        RateLimiter(maxRate: .infinity, burst: .infinity, coolOff: .zero)
    }

    private let maxRate: Double
    private let minRate: Double
    private let burst: Double
    private let coolOff: Duration
    private let recoveryStreak: Int
    private let logger = NetworkLogger.shared

    // The most a Retry-After is allowed to last. A wild server value shouldn't be able
    // to mute the app for half a minute on a header's say-so.
    private static let maxRetryAfter: Duration = .seconds(30)

    private var rate: Double
    private var tokens: Double
    private var lastRefill: ContinuousClock.Instant

    // Until when to stop requesting, and how many 429s in a row
    private var coolOffUntil: ContinuousClock.Instant?
    private var consecutiveRateLimits = 0
    private var successStreak = 0

    // When the brake was last set. Separates "another 429" from "the same 429": anything
    // already in flight when the brake went on belongs to the burst that caused it, and
    // can't count as a new streak.
    private var holdStartedAt: ContinuousClock.Instant?

    // internal so tests can check the brake and rate without watching the clock
    var isCoolingOff: Bool { remainingCoolOff != nil }
    var currentRate: Double { rate }

    var remainingCoolOff: Duration? {
        guard let coolOffUntil else { return nil }
        let remaining = ContinuousClock.now.duration(to: coolOffUntil)
        return remaining > .zero ? remaining : nil
    }

    // Defaults are a starting point, not a measurement — Cloudflare's threshold isn't
    // documented, so this starts cautious and the rate self-adjusts. Eight per second
    // fills a fling's landing screen in under a second and warms a page of twenty in
    // 2.5s; at reading speed, it's plenty.
    init(
        maxRate: Double = 8,
        burst: Double = 8,
        minRate: Double = 2,
        coolOff: Duration = .seconds(2),
        recoveryStreak: Int = 30
    ) {
        self.maxRate = maxRate
        self.minRate = min(minRate, maxRate)
        self.burst = max(1, burst)
        self.coolOff = coolOff
        self.recoveryStreak = max(1, recoveryStreak)
        self.rate = maxRate
        self.tokens = self.burst
        self.lastRefill = .now
    }

    // Waits until the network is fair game and spends a token. Called right before
    // every real request, at the two places they're made: the HTTP client and image
    // downloads.
    //
    // A loop, not a wait queue, on purpose: at most five tasks wait here at once — the
    // download queue's four slots plus the page in flight — and with so few, sleeping
    // the shortfall and checking again is simpler and just as fair. Ordering comes from
    // the LIFO download queue; this only rations.
    func acquire() async throws(AppError) {
        while true {
            if let remaining = remainingCoolOff {
                try await sleep(remaining)
                continue
            }

            // No rate (tests) means no tokens to count — and this has to return before
            // touching the math, since infinity times zero is NaN.
            guard rate.isFinite else { return }

            refill()
            if tokens >= 1 {
                tokens -= 1
                return
            }
            try await sleep(.seconds((1 - tokens) / rate))
        }
    }

    // The server said we're going too fast. Everyone stops and the rate drops —
    // retrying at the same pace would just extend the penalty.
    //
    // issuedAt is when the request that got the 429 went out (callers take it right
    // after acquire()), and it's what keeps one burst from counting as several streaks.
    // When Cloudflare cuts in, the download queue's four slots and the page in flight
    // all come back 429 at once; counted one by one, a single server warning left the
    // brake at sixteen seconds and the rate on the floor, needing 180 successes to climb
    // back. Since acquire() lets nothing out while the brake holds, everything that went
    // out before it was set belongs to the burst that caused it — the first 429 sets the
    // brake, the rest add nothing. Only a 429 from a request issued after the brake was
    // set (i.e. after it lifted) counts as "again." Same as TCP: halve once per loss,
    // not once per packet.
    func reportRateLimited(retryAfter: Duration?, issuedAt: ContinuousClock.Instant = .now) {
        // No rate (tests, previews) means no brake either, whatever the header says.
        guard rate.isFinite else { return }
        if let holdStartedAt, issuedAt < holdStartedAt { return }

        consecutiveRateLimits += 1
        successStreak = 0

        // Each 429 in a row doubles the wait, up to 8x the base. If the server names a
        // duration, that wins.
        let backoff = coolOff * (1 << min(consecutiveRateLimits - 1, 3))
        let hold = retryAfter.map { min($0, Self.maxRetryAfter) } ?? backoff
        let now = ContinuousClock.now
        let until = now.advanced(by: hold)
        coolOffUntil = until
        holdStartedAt = now

        // Tokens empty and stay empty until the brake lifts — refilling in the meantime
        // would let a full burst out the moment it does, exactly what the server just
        // said not to do.
        tokens = 0
        lastRefill = until

        let previous = rate
        rate = max(minRate, rate / 2)
        logger.logThrottle("⏳ Rate limited · hold \(hold) · rate \(previous)→\(rate) req/s")
    }

    // A success resets the 429 streak and, every so often, gives back a bit of rate.
    // Climbs by one, halves on a hit: cheaper to err on the slow side than to earn the
    // brake again.
    //
    // Same issuedAt logic as above: a success from a request already in flight when the
    // brake was set says nothing about the server's state now, so it neither clears the
    // 429 streak nor counts toward recovery.
    func reportSuccess(issuedAt: ContinuousClock.Instant = .now) {
        if let holdStartedAt, issuedAt < holdStartedAt { return }

        consecutiveRateLimits = 0
        guard rate < maxRate else {
            successStreak = 0
            return
        }

        successStreak += 1
        guard successStreak >= recoveryStreak else { return }
        successStreak = 0

        let previous = rate
        rate = min(maxRate, rate + 1)
        logger.logThrottle("🔼 Rate recovering · \(previous)→\(rate) req/s")
    }

    // MARK: - Tokens

    private func refill() {
        let now = ContinuousClock.now
        // lastRefill can sit in the future right after a 429 — nothing to add until then.
        guard now > lastRefill else { return }
        let elapsed = lastRefill.duration(to: now)
        lastRefill = now
        tokens = min(burst, tokens + Self.seconds(elapsed) * rate)
    }

    private func sleep(_ duration: Duration) async throws(AppError) {
        do {
            try await Task.sleep(for: duration)
        } catch {
            // sleep only throws on cancellation: whoever was waiting no longer wants out.
            throw .cancelled
        }
    }

    private static func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) * 1e-18
    }
}

extension HTTPURLResponse {
    // A 429's Retry-After, if present and in seconds. The date form is ignored:
    // Cloudflare doesn't send it, and parsing it would be more code than it's worth.
    var retryAfter: Duration? {
        guard let raw = value(forHTTPHeaderField: "Retry-After")?
                .trimmingCharacters(in: .whitespaces),
              let seconds = Int(raw), seconds > 0
        else { return nil }
        return .seconds(seconds)
    }
}
