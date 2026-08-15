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

        // Seis peticiones a la vez, que es lo que produce una pantalla de grid
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

            await gate.waitUntilReached()
            await gate.open()
        }

        #expect(await probe.peak == 2)
    }

    @Test("When a slot frees up, the last request queued goes first")
    func servesTheLastRequestFirst() async throws {
        // Es el corazón del asunto: al bajar rápido, la última imagen pedida es la que
        // el usuario tiene delante y la primera es una que dejó atrás hace diez
        // pantallas. En orden de llegada el usuario vería pintarse todas las que ya no
        // mira antes de que le llegue la suya.
        let gate = AsyncGate()
        let order = OrderRecorder()
        let sut = DownloadQueue(limit: 1)

        async let running: Void = enqueue(0, on: sut, recordingInto: order, blockingOn: gate)
        await gate.waitUntilReached()

        // Se encolan de una en una para que el orden de llegada sea el que dice el
        // test y no el que decida el planificador
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
        // Con LIFO, a una espera cancelada no la despierta el turno: siempre hay
        // alguien más nuevo por delante. Si no se la saca de la cola a mano, esa tarea
        // se queda aparcada para siempre.
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

    @Test("A rate limited download puts every other download on hold, not just itself")
    func aRateLimitHoldsTheWholeQueue() async throws {
        // Es lo que separa recuperarse de hundirse más: si cada imagen reintentase su
        // propio 429, el reintento repetiría la ráfaga que se ganó el límite y ya no se
        // saldría de ahí. El freno es compartido porque el límite también lo es.
        let sut = DownloadQueue(limit: 4, coolOff: .milliseconds(80))

        await #expect(throws: AppError.rateLimited) {
            _ = try await sut.enqueue { () async throws(AppError) -> Data in throw .rateLimited }
        }

        #expect(await sut.isCoolingOff)
    }

    @Test("The hold lifts on its own, and a success clears the record")
    func theHoldLiftsOnItsOwn() async throws {
        let sut = DownloadQueue(limit: 4, coolOff: .milliseconds(50))
        _ = try? await sut.enqueue { () async throws(AppError) -> Data in throw .rateLimited }

        // La siguiente no falla: espera a que pase el freno y entra
        let data = try await sut.enqueue { Data("ok".utf8) }

        #expect(data == Data("ok".utf8))
        #expect(await sut.isCoolingOff == false)
    }

    // MARK: - Helpers

    private func enqueue(
        _ id: Int,
        on queue: DownloadQueue,
        recordingInto order: OrderRecorder,
        blockingOn gate: AsyncGate? = nil
    ) async {
        _ = try? await queue.enqueue {
            await order.record(id)
            if let gate { await gate.wait() }
            return Data()
        }
    }

    // Se cede el turno en vez de dormir: no depende del reloj, así que no falla en una
    // máquina lenta
    private func waitUntilWaiting(_ count: Int, in queue: DownloadQueue) async throws {
        for _ in 0..<10_000 {
            if await queue.waitingCount == count { return }
            await Task.yield()
        }
        Issue.record("The queue never reached \(count) waiting requests")
    }
}
