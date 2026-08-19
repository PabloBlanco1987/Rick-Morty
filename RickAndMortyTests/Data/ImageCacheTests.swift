import CoreGraphics
import Foundation
import Testing
@testable import RickAndMorty

extension RetryPolicy {
    // Retries without delay: what a test cares about is that it retries, not how long
    // it sleeps — keeps the suite in milliseconds
    static let immediate = RetryPolicy(maxAttempts: 3, baseDelay: .zero, rateLimitedDelay: .zero)
}

@Suite("Image cache")
struct ImageCacheTests {
    private let url = URL(filePath: "/avatars/1.jpeg")
    // A 100pt cell at 2x scale is 200px: the fixture is 600px, so if downsampling
    // doesn't happen it shows up in the resulting image's width
    private let cellSize = CGSize(width: 100, height: 100)
    private let scale: CGFloat = 2

    @Test("The image is decoded at the size of the cell, not at the size of the file")
    func downsamplesToTheCellSize() async throws {
        try await withTemporaryDirectory { directory in
            let loader = CountingImageLoader(returning: try ImageFixtures.png(side: 600))
            let sut = ImageCache(directory: directory, settleDelay: .zero, loader: loader.load)

            let loaded = try await sut.image(for: url, size: cellSize, scale: scale)

            #expect(loaded.image.width == 200)
            #expect(loaded.image.height == 200)
        }
    }

    @Test("The same URL at the same size comes back from memory the second time")
    func servesTheSecondRequestFromMemory() async throws {
        try await withTemporaryDirectory { directory in
            let loader = CountingImageLoader(returning: try ImageFixtures.png(side: 600))
            let sut = ImageCache(directory: directory, settleDelay: .zero, loader: loader.load)

            let first = try await sut.image(for: url, size: cellSize, scale: scale)
            let second = try await sut.image(for: url, size: cellSize, scale: scale)

            #expect(first.origin == .network)
            #expect(second.origin == .memory)
            #expect(await loader.callCount == 1)
        }
    }

    @Test("A cache that starts with an empty memory finds the bytes on disk")
    func servesFromDiskWithAColdMemory() async throws {
        try await withTemporaryDirectory { directory in
            // Two instances over the same directory: this is what happens across two
            // app launches, with memory empty and disk already populated.
            let loader = CountingImageLoader(returning: try ImageFixtures.png(side: 600))
            let first = ImageCache(directory: directory, settleDelay: .zero, loader: loader.load)
            _ = try await first.image(for: url, size: cellSize, scale: scale)

            let second = ImageCache(directory: directory, settleDelay: .zero, loader: loader.load)
            let loaded = try await second.image(for: url, size: cellSize, scale: scale)

            #expect(loaded.origin == .disk)
            #expect(await loader.callCount == 1)
        }
    }

    @Test("Two concurrent requests for the same URL only trigger one download")
    func deduplicatesConcurrentRequests() async throws {
        try await withTemporaryDirectory { directory in
            // The gate freezes the first download inside the loader, so the second
            // request arrives while the first is still in flight. Without it we'd have
            // to sleep and hope, which is how you write tests that fail one time in
            // thirty.
            let gate = AsyncGate()
            let loader = CountingImageLoader(
                returning: try ImageFixtures.png(side: 600),
                beforeReturning: { await gate.wait() }
            )
            let sut = ImageCache(directory: directory, settleDelay: .zero, loader: loader.load)

            async let first = sut.image(for: url, size: cellSize, scale: scale)
            await gate.waitUntilReached()
            async let second = sut.image(for: url, size: cellSize, scale: scale)
            await gate.open()

            let images = try await [first, second]

            #expect(await loader.callCount == 1)
            #expect(images.allSatisfy { $0.image.width == 200 })
        }
    }

    @Test("A download nobody is waiting for any more is cancelled, not left in the queue")
    func cancelsDownloadsNobodyIsWaitingFor() async throws {
        try await withTemporaryDirectory { directory in
            // This is the difference between a fast scroll that fills back in and one
            // that leaves the grid gray: URLSession opens six connections per host, so a
            // request nobody cares about any more isn't free — it's taking a slot from a
            // cell that's actually visible.
            let gate = AsyncGate()
            let loader = CountingImageLoader(
                returning: try ImageFixtures.png(side: 600),
                beforeReturning: { await gate.wait() }
            )
            let sut = ImageCache(directory: directory, settleDelay: .zero, loader: loader.load)

            let request = Task { try await sut.image(for: url, size: cellSize, scale: scale) }
            await gate.waitUntilReached()
            request.cancel()
            await waitUntilNothingIsInFlight(in: sut)

            await gate.open()
            _ = try? await request.value

            #expect(await loader.wasCancelled)
        }
    }

    @Test("A cell the user scrolled straight past never costs a request")
    func doesNotSpendARequestOnACellThatWentBy() async throws {
        try await withTemporaryDirectory { directory in
            // In a quick glance, cells appear and disappear within tens of milliseconds.
            // Requesting those images isn't just wasted bandwidth: it's the burst that
            // gets the API to answer 429 and take down the next page's loading with it.
            let loader = CountingImageLoader(returning: try ImageFixtures.png(side: 600))
            let sut = ImageCache(
                directory: directory,
                settleDelay: .milliseconds(200),
                loader: loader.load
            )

            let request = Task { try await sut.image(for: url, size: cellSize, scale: scale) }
            // The cell leaves before it has time to settle
            request.cancel()
            _ = try? await request.value

            #expect(await loader.callCount == 0)
        }
    }

    @Test("A cell that stays on screen gets its image once it has settled")
    func aCellThatStaysIsRequestedAfterSettling() async throws {
        try await withTemporaryDirectory { directory in
            // The flip side of the previous test: the delay exists to avoid wasting
            // requests on cells that leave, not to slow down the ones that stay. This
            // checks that the delay happens and the request follows; a slow machine can
            // only stretch it.
            let loader = CountingImageLoader(returning: try ImageFixtures.png(side: 600))
            let sut = ImageCache(directory: directory, settleDelay: .milliseconds(50), loader: loader.load)

            let elapsed = try await ContinuousClock().measure {
                _ = try await sut.image(for: url, size: cellSize, scale: scale)
            }

            #expect(elapsed >= .milliseconds(40))
            #expect(await loader.callCount == 1)
        }
    }

    @Test("The same URL at two sizes gives two bitmaps out of a single download")
    func reusesTheBytesAcrossSizes() async throws {
        try await withTemporaryDirectory { directory in
            // The bytes are kept undownsampled for exactly this: a different size costs
            // a decode, not another download.
            let loader = CountingImageLoader(returning: try ImageFixtures.png(side: 600))
            let sut = ImageCache(directory: directory, settleDelay: .zero, loader: loader.load)

            let small = try await sut.image(for: url, size: cellSize, scale: scale)
            let large = try await sut.image(for: url, size: CGSize(width: 300, height: 300), scale: scale)

            #expect(small.image.width == 200)
            #expect(large.image.width == 600)
            #expect(await loader.callCount == 1)
        }
    }

    @Test("Bytes that are not an image are a decoding failure, not a crash")
    func rejectsBytesThatAreNotAnImage() async throws {
        try await withTemporaryDirectory { directory in
            let loader = CountingImageLoader(returning: Data("not an image".utf8))
            let sut = ImageCache(directory: directory, settleDelay: .zero, loader: loader.load)

            await #expect(throws: AppError.decoding) {
                _ = try await sut.image(for: url, size: cellSize, scale: scale)
            }
        }
    }

    @Test("A download that fails with something worth retrying is retried")
    func retriesWhatIsWorthRetrying() async throws {
        try await withTemporaryDirectory { directory in
            // Without the retry, a transient 503 leaves that cell gray until the user
            // scrolls it off screen and back on — that's the only thing that re-fires
            // its .task.
            // The loader's default failure is a 503: the textbook transient hiccup
            let loader = CountingImageLoader(returning: try ImageFixtures.png(side: 600), failingFirst: 1)
            // No delay between attempts: what's under test is that it retries, not how
            // long it sleeps, so the suite stays in milliseconds
            let sut = ImageCache(
                directory: directory,
                settleDelay: .zero,
                loader: ImageCache.retrying(loader.load, policy: .immediate)
            )

            let loaded = try await sut.image(for: url, size: cellSize, scale: scale)

            #expect(loaded.image.width == 200)
            #expect(await loader.callCount == 2)
        }
    }

    @Test("A download that fails with something not worth retrying is not retried")
    func doesNotRetryWhatIsNotWorthRetrying() async throws {
        try await withTemporaryDirectory { directory in
            let loader = CountingImageLoader(
                returning: try ImageFixtures.png(side: 600),
                failingFirst: 5,
                with: .notFound
            )
            let sut = ImageCache(
                directory: directory,
                settleDelay: .zero,
                loader: ImageCache.retrying(loader.load, policy: .immediate)
            )

            await #expect(throws: AppError.notFound) {
                _ = try await sut.image(for: url, size: cellSize, scale: scale)
            }
            #expect(await loader.callCount == 1)
        }
    }

    @Test("A download that fails surfaces the error it failed with")
    func propagatesTheDownloadFailure() async throws {
        try await withTemporaryDirectory { directory in
            let sut = ImageCache(directory: directory, settleDelay: .zero) { _ throws(AppError) in throw .offline }

            await #expect(throws: AppError.offline) {
                _ = try await sut.image(for: url, size: cellSize, scale: scale)
            }
        }
    }

    @Test("Being rate limited is not retried here: the shared limiter owns that")
    func doesNotRetryRateLimiting() async throws {
        try await withTemporaryDirectory { directory in
            // A 429 is retryable for the HTTP client, but retrying it per image would
            // mean each of four in-flight downloads repeating on its own the burst that
            // got us rate-limited in the first place. RateLimiter's shared throttle
            // handles that once, for everyone.
            let loader = CountingImageLoader(
                returning: try ImageFixtures.png(side: 600),
                failingFirst: 5,
                with: .rateLimited
            )
            let sut = ImageCache(
                directory: directory,
                settleDelay: .zero,
                loader: ImageCache.retrying(loader.load, policy: .immediate)
            )

            await #expect(throws: AppError.rateLimited) {
                _ = try await sut.image(for: url, size: cellSize, scale: scale)
            }
            #expect(await loader.callCount == 1)
        }
    }

    @Test("Bytes that do not decode are not kept: the next attempt goes back to the network")
    func doesNotKeepBytesThatDoNotDecode() async throws {
        try await withTemporaryDirectory { directory in
            // What a captive portal does: a hotel's wifi answers 200 with its login page.
            // The download saves the bytes before knowing whether they decode, and if
            // they stayed on disk, every later visit would read them from there, fail
            // the same way, and never download the real image again.
            let loader = CountingImageLoader(returningInOrder: [
                Data("<html>hotel wifi login</html>".utf8),
                try ImageFixtures.png(side: 600),
            ])
            let sut = ImageCache(directory: directory, settleDelay: .zero, loader: loader.load)

            await #expect(throws: AppError.decoding) {
                _ = try await sut.image(for: url, size: cellSize, scale: scale)
            }
            let loaded = try await sut.image(for: url, size: cellSize, scale: scale)

            // From the network, not disk: the broken bytes were deleted
            #expect(loaded.origin == .network)
            #expect(loaded.image.width == 200)
            #expect(await loader.callCount == 2)
        }
    }

    @Test("Cancelling one of two cells sharing a download leaves the other's download running")
    func cancellingOneWaiterKeepsTheDownloadForTheOther() async throws {
        try await withTemporaryDirectory { directory in
            // This is why it tracks a count of interested waiters instead of a flag: the
            // download only cancels when the last one leaves. If it cancelled with the
            // first, a cell scrolling off screen would leave its neighbor — still
            // watching it — without an image.
            let gate = AsyncGate()
            let loader = CountingImageLoader(
                returning: try ImageFixtures.png(side: 600),
                beforeReturning: { await gate.wait() }
            )
            let sut = ImageCache(directory: directory, settleDelay: .zero, loader: loader.load)

            let first = Task { try await sut.image(for: url, size: cellSize, scale: scale) }
            await gate.waitUntilReached()
            let second = Task { try await sut.image(for: url, size: cellSize, scale: scale) }
            await waitUntil(2, areWaitingFor: url, in: sut)

            first.cancel()
            await waitUntil(1, areWaitingFor: url, in: sut)
            await gate.open()

            let loaded = try await second.value
            #expect(loaded.image.width == 200)
            #expect(await loader.callCount == 1)
            #expect(await loader.wasCancelled == false)
            await #expect(throws: AppError.cancelled) { _ = try await first.value }
        }
    }
}
