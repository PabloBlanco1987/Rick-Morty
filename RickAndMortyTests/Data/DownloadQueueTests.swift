import Foundation
import Testing
@testable import RickAndMorty

@Suite("Download queue")
struct DownloadQueueTests {
    @Test("No more downloads run at the same time than the limit allows")
    func respectsTheLimit() async throws {
        let gate = AsyncGate()
        let probe = ConcurrencyProbe()
        let sut = DownloadQueue(limit: 2)

        // Six requests at once, matching what a grid screen produces
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<6 {
                group.addTask {
                    _ = try? await sut.enqueue {
                        await probe.enter()
                        await gate.wait()
                        await probe.leave()
                        return Data()
                    }
                }
            }

            // Before opening: the two that fit are in, the other four are waiting for a
            // slot. This proves nobody else got through, so the peak measured next is
            // the real one, not just whoever arrived first.
            for _ in 0..<10_000 {
                if await probe.current == 2 { break }
                await Task.yield()
            }
            try? await waitUntilWaiting(4, in: sut)
            await gate.open()
        }

        #expect(await probe.peak == 2)
    }

    @Test("When a slot frees up, the last request queued goes first")
    func servesTheLastRequestFirst() async throws {
        // The heart of it: when scrolling fast, the last image requested is the one in
        // front of the user, while the first is one left behind ten screens ago. In
        // arrival order, the user would see every image they've stopped looking at
        // render before their own.
        let gate = AsyncGate()
        let order = OrderRecorder()
        let sut = DownloadQueue(limit: 1)

        async let running: Void = enqueue(0, on: sut, recordingInto: order, blockingOn: gate)
        await gate.waitUntilReached()

        // Enqueued one at a time so arrival order matches the test, not whatever the
        // scheduler decides
        async let first: Void = enqueue(1, on: sut, recordingInto: order)
        try await waitUntilWaiting(1, in: sut)
        async let second: Void = enqueue(2, on: sut, recordingInto: order)
        try await waitUntilWaiting(2, in: sut)
        async let third: Void = enqueue(3, on: sut, recordingInto: order)
        try await waitUntilWaiting(3, in: sut)

        await gate.open()
        _ = await (running, first, second, third)

        #expect(await order.ids == [0, 3, 2, 1])
    }

    @Test("A request cancelled while queued lets go of its place instead of parking forever")
    func releasesTheQueueWhenCancelled() async throws {
        // With LIFO, a cancelled wait is never woken by its turn — there's always
        // someone newer ahead of it. Without removing it from the queue by hand, that
        // task would stay parked forever.
        let gate = AsyncGate()
        let sut = DownloadQueue(limit: 1)

        async let running: Void = enqueue(0, on: sut, recordingInto: OrderRecorder(), blockingOn: gate)
        await gate.waitUntilReached()

        let queued = Task { _ = try? await sut.enqueue { Data() } }
        try await waitUntilWaiting(1, in: sut)

        queued.cancel()
        await queued.value

        #expect(await sut.waitingCount == 0)
        await gate.open()
        await running
    }

    @Test("A download that fails hands its slot back")
    func aFailingDownloadReleasesItsSlot() async throws {
        // A 503 on one image can't leave its slot occupied forever: with four slots,
        // four failures in a row would starve the whole grid of downloads
        let order = OrderRecorder()
        let sut = DownloadQueue(limit: 1)

        await #expect(throws: AppError.server(statusCode: 503)) {
            try await sut.enqueue { () async throws(AppError) -> Data in throw .server(statusCode: 503) }
        }

        // In a separate task with a deadline: if the slot had stayed stuck, waiting
        // here would hang the test instead of just suspending it
        let next = Task { await enqueue(1, on: sut, recordingInto: order) }
        for _ in 0..<10_000 {
            if await !order.ids.isEmpty { break }
            await Task.yield()
        }
        next.cancel()
        await next.value

        #expect(await order.ids == [1], "The slot the failed download held was never handed back")
    }

    @Test("A request cancelled while queued fails as cancelled and never runs its work")
    func aCancelledRequestDoesNotRunItsWork() async throws {
        let gate = AsyncGate()
        let sut = DownloadQueue(limit: 1)
        let probe = ConcurrencyProbe()

        async let running: Void = enqueue(0, on: sut, recordingInto: OrderRecorder(), blockingOn: gate)
        await gate.waitUntilReached()

        let queued = Task {
            try await sut.enqueue { () async throws(AppError) -> Data in
                await probe.enter()
                return Data()
            }
        }
        try await waitUntilWaiting(1, in: sut)
        queued.cancel()

        await #expect(throws: AppError.cancelled) { try await queued.value }
        #expect(await probe.peak == 0)
        await gate.open()
        await running
    }

    // MARK: - Priority

    @Test("A prefetch only gets a slot when nothing visible is waiting")
    func prefetchGoesAfterEverythingVisible() async throws {
        // Warming the next page can't steal a slot from a cell that's on screen, even
        // if it queued first: the prefetch enqueues first, yet the visible requests
        // still go ahead of it, and LIFO still applies among them.
        let gate = AsyncGate()
        let order = OrderRecorder()
        let sut = DownloadQueue(limit: 1)

        async let running: Void = enqueue(0, on: sut, recordingInto: order, blockingOn: gate)
        await gate.waitUntilReached()

        async let prefetch: Void = enqueue(1, priority: .prefetch, on: sut, recordingInto: order)
        try await waitUntilWaiting(1, in: sut)
        async let firstVisible: Void = enqueue(2, on: sut, recordingInto: order)
        try await waitUntilWaiting(2, in: sut)
        async let secondVisible: Void = enqueue(3, on: sut, recordingInto: order)
        try await waitUntilWaiting(3, in: sut)

        await gate.open()
        _ = await (running, prefetch, firstVisible, secondVisible)

        #expect(await order.ids == [0, 3, 2, 1])
    }

    // MARK: - Pause

    @Test("While paused no slot is handed out, and resuming hands them out again")
    func pauseHoldsSlotsUntilResumed() async throws {
        // What holds the network back during a fling: the queue keeps accepting
        // requests, but doesn't release them until the scroll stops
        let sut = DownloadQueue(limit: 2)
        let order = OrderRecorder()

        await sut.setPaused(true)
        async let held: Void = enqueue(1, on: sut, recordingInto: order)
        try await waitUntilWaiting(1, in: sut)
        #expect(await order.ids.isEmpty)

        await sut.setPaused(false)
        await held

        #expect(await order.ids == [1])
        #expect(await sut.waitingCount == 0)
    }

    @Test("A slot freed while paused is not handed over to the next in line")
    func pauseDoesNotHandOverFreedSlots() async throws {
        // Without this, pausing would only hold back new requests: the ones already
        // waiting would keep trickling out as each slot freed up
        let gate = AsyncGate()
        let order = OrderRecorder()
        let sut = DownloadQueue(limit: 1)

        async let running: Void = enqueue(0, on: sut, recordingInto: order, blockingOn: gate)
        await gate.waitUntilReached()
        async let queued: Void = enqueue(1, on: sut, recordingInto: order)
        try await waitUntilWaiting(1, in: sut)

        await sut.setPaused(true)
        await gate.open()
        await running

        // The slot freed up, and the one waiting is still waiting
        #expect(await order.ids == [0])
        #expect(await sut.waitingCount == 1)

        await sut.setPaused(false)
        await queued
        #expect(await order.ids == [0, 1])
    }

    @Test("A pause that nobody lifts expires on its own")
    func pauseExpiresOnItsOwn() async throws {
        // If the view disappears mid-fling and never resumes, the queue can't stay dead
        // with every image in the app stuck inside it. This actually waits, but only
        // for the timeout to expire — oversleeping can't break it.
        let sut = DownloadQueue(limit: 1, pauseTimeout: .milliseconds(50))
        let order = OrderRecorder()

        await sut.setPaused(true)
        await enqueue(1, on: sut, recordingInto: order)

        #expect(await order.ids == [1])
        #expect(await sut.isPaused == false)
    }

    @Test("A stale timer from an earlier pause does not lift a newer one")
    func anEarlierPauseTimerDoesNotLiftALaterPause() async throws {
        // Pause, resume, pause again leaves the first pause's timer alive. Without the
        // generation counter, that timer would lift the second pause early, and a
        // chained fling would release requests mid-gesture again.
        //
        // This uses the real clock, with margin: the first pause expires at 1s, the
        // second at 1.5s, checked at 1.25s. A slow machine stretches the sleeps, and the
        // only risk is the check itself running a quarter-second late — far more slack
        // than a task needs to wake up.
        let sut = DownloadQueue(limit: 1, pauseTimeout: .seconds(1))
        let order = OrderRecorder()

        await sut.setPaused(true)
        try await Task.sleep(for: .milliseconds(500))
        await sut.setPaused(false)
        await sut.setPaused(true)
        async let held: Void = enqueue(1, on: sut, recordingInto: order)
        try await waitUntilWaiting(1, in: sut)

        // The first pause's timeout has already passed, and the second pause is still on
        try await Task.sleep(for: .milliseconds(750))
        #expect(await sut.isPaused, "The first pause's timer lifted the second pause")
        #expect(await order.ids.isEmpty)

        // And the second pause expires when its own turn comes
        await held
        #expect(await order.ids == [1])
    }

    // MARK: - Helpers

    private func enqueue(
        _ id: Int,
        priority: DownloadQueue.Priority = .visible,
        on queue: DownloadQueue,
        recordingInto order: OrderRecorder,
        blockingOn gate: AsyncGate? = nil
    ) async {
        _ = try? await queue.enqueue(priority: priority) {
            await order.record(id)
            if let gate { await gate.wait() }
            return Data()
        }
    }

    // Yields instead of sleeping: doesn't depend on the clock, so it won't fail on a
    // slow machine
    private func waitUntilWaiting(_ count: Int, in queue: DownloadQueue) async throws {
        for _ in 0..<10_000 {
            if await queue.waitingCount == count { return }
            await Task.yield()
        }
        Issue.record("The queue never reached \(count) waiting requests")
    }
}
