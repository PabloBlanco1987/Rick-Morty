import CoreGraphics
import Foundation
import Testing
@testable import RickAndMorty

/// Warming the next page and pausing during a fling: the two mechanisms that make
/// cells arrive with their image already loaded at reading speed, and keep a fling
/// from spending its budget on cells nobody ends up seeing.
@Suite("Image cache warm-up and pause")
struct ImageCacheWarmUpTests {
    private let url = URL(filePath: "/avatars/1.jpeg")
    private let cellSize = CGSize(width: 100, height: 100)
    private let scale: CGFloat = 2

    // MARK: - Warm-up

    @Test("Warming a page leaves its images on disk, so the cells find them without a download")
    func warmingLeavesTheBytesOnDisk() async throws {
        try await withTemporaryDirectory { directory in
            // The feel of an app that "already had it": once the user scrolls to a page
            // that just arrived, its cells load from disk, not the network.
            let loader = CountingImageLoader(returning: try ImageFixtures.png(side: 600))
            let sut = ImageCache(directory: directory, settleDelay: .zero, loader: loader.load)
            let urls = [URL(filePath: "/avatars/1.jpeg"), URL(filePath: "/avatars/2.jpeg")]

            await sut.warm(urls)
            let loaded = try await sut.image(for: urls[1], size: cellSize, scale: scale)

            #expect(loaded.origin == .disk)
            #expect(await loader.callCount == 2)
        }
    }

    @Test("Warming what is already on disk costs no download")
    func warmingSkipsWhatIsOnDisk() async throws {
        try await withTemporaryDirectory { directory in
            // What's already stored is never requested — this is what makes re-warming
            // an already-seen page (scrolling back and forth) free.
            let loader = CountingImageLoader(returning: try ImageFixtures.png(side: 600))
            let sut = ImageCache(directory: directory, settleDelay: .zero, loader: loader.load)
            _ = try await sut.image(for: url, size: cellSize, scale: scale)

            await sut.warm([url])

            #expect(await loader.callCount == 1)
        }
    }

    @Test("A warm-up does not wait for a cell to settle: there is no cell")
    func warmingDoesNotSettle() async throws {
        try await withTemporaryDirectory { directory in
            // Settling exists to avoid spending a request on a cell that's scrolling away.
            // A warm-up isn't a cell: with a 10-second settle delay, finishing right away
            // can only mean it never waited.
            let loader = CountingImageLoader(returning: try ImageFixtures.png(side: 600))
            let sut = ImageCache(directory: directory, settleDelay: .seconds(10), loader: loader.load)

            let elapsed = await ContinuousClock().measure { await sut.warm([url]) }

            #expect(await loader.callCount == 1)
            #expect(elapsed < .seconds(5))
        }
    }

    @Test("Cancelling a warm-up stops it at the image in flight and asks for no more")
    func cancellingAWarmUpStopsIt() async throws {
        try await withTemporaryDirectory { directory in
            // When the next page arrives, the view cancels the previous page's warm-up:
            // what was in flight gets cancelled and what remained is never requested.
            let gate = AsyncGate()
            let loader = CountingImageLoader(
                returning: try ImageFixtures.png(side: 600),
                beforeReturning: { await gate.wait() }
            )
            let sut = ImageCache(directory: directory, settleDelay: .zero, loader: loader.load)
            let urls = [URL(filePath: "/avatars/1.jpeg"), URL(filePath: "/avatars/2.jpeg")]

            let warming = Task { await sut.warm(urls) }
            await gate.waitUntilReached()
            warming.cancel()
            // The download stays blocked at the gate until it opens: first confirm the
            // cancellation has landed, then open the gate and let it finish
            await waitUntilNothingIsInFlight(in: sut)
            await gate.open()
            await warming.value

            #expect(await loader.callCount == 1)
            #expect(await loader.wasCancelled)
        }
    }

    @Test("A visible cell that asks for an image being warmed joins that download")
    func aCellJoinsAWarmUpInFlight() async throws {
        try await withTemporaryDirectory { directory in
            let gate = AsyncGate()
            let loader = CountingImageLoader(
                returning: try ImageFixtures.png(side: 600),
                beforeReturning: { await gate.wait() }
            )
            let sut = ImageCache(directory: directory, settleDelay: .zero, loader: loader.load)

            async let warming: Void = sut.warm([url])
            await gate.waitUntilReached()
            async let cell = sut.image(for: url, size: cellSize, scale: scale)
            await gate.open()

            let loaded = try await cell
            await warming

            #expect(loaded.image.width == 200)
            #expect(await loader.callCount == 1)
        }
    }

    // MARK: - Pause

    @Test("With the network paused a download waits; resuming lets it through")
    func pausingHoldsTheNetwork() async throws {
        try await withTemporaryDirectory { directory in
            let loader = CountingImageLoader(returning: try ImageFixtures.png(side: 600))
            let sut = ImageCache(directory: directory, settleDelay: .zero, loader: loader.load)

            await sut.setNetworkPaused(true)
            let request = Task { try await sut.image(for: url, size: cellSize, scale: scale) }
            await waitUntilSomethingIsWaiting(in: sut)
            #expect(await loader.callCount == 0)

            await sut.setNetworkPaused(false)
            let loaded = try await request.value

            #expect(loaded.origin == .network)
        }
    }
}
