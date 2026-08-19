import Foundation
import Testing
@testable import RickAndMorty

// Shared helpers for the image cache suites.

// A private directory per test, removed on exit — otherwise a test could read what
// another left on disk and cache hits would stop meaning anything.
func withTemporaryDirectory<T>(_ body: (URL) async throws -> T) async throws -> T {
    let directory = URL.temporaryDirectory.appending(
        path: UUID().uuidString,
        directoryHint: .isDirectory
    )
    defer { try? FileManager.default.removeItem(at: directory) }
    return try await body(directory)
}

// A cancelled subscriber's removal happens on a separate Task — onCancel is synchronous
// and outside the actor — so we must wait for it to land. Yields instead of sleeping:
// doesn't depend on the clock, so it won't flake on a slow machine.
func waitUntilNothingIsInFlight(in cache: ImageCache) async {
    for _ in 0..<10_000 {
        if await cache.inFlightCount == 0 { return }
        await Task.yield()
    }
    Issue.record("The download was still in flight after its only request was cancelled")
}

// Same idea, to know a download has reached the queue and is waiting for a slot.
func waitUntilSomethingIsWaiting(in cache: ImageCache) async {
    for _ in 0..<10_000 {
        if await cache.waitingDownloadCount > 0 { return }
        await Task.yield()
    }
    Issue.record("No download ever reached the queue")
}

// Same again, to know that many cells have latched onto one URL's download.
func waitUntil(_ count: Int, areWaitingFor url: URL, in cache: ImageCache) async {
    for _ in 0..<10_000 {
        if await cache.waiterCount(for: url) == count { return }
        await Task.yield()
    }
    Issue.record("The download never reached \(count) waiters")
}
