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

    // MARK: - Prioridad

    @Test("A prefetch only gets a slot when nothing visible is waiting")
    func prefetchGoesAfterEverythingVisible() async throws {
        // El precalentamiento de la página siguiente no puede quitarle el hueco a una
        // celda que se está mirando, aunque haya llegado antes: se encola el prefetch
        // primero y aun así las visibles pasan por delante, y entre ellas sigue el LIFO.
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

    // MARK: - Pausa

    @Test("While paused no slot is handed out, and resuming hands them out again")
    func pauseHoldsSlotsUntilResumed() async throws {
        // Es lo que retiene la red durante un fling: la cola sigue aceptando peticiones,
        // pero no las suelta hasta que el scroll para
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
        // Sin esto, pausar solo frenaría las peticiones nuevas: las que ya esperaban
        // irían saliendo una a una según se liberase cada hueco
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

        // El hueco se ha liberado y el que esperaba sigue esperando
        #expect(await order.ids == [0])
        #expect(await sut.waitingCount == 1)

        await sut.setPaused(false)
        await queued
        #expect(await order.ids == [0, 1])
    }

    @Test("A pause that nobody lifts expires on its own")
    func pauseExpiresOnItsOwn() async throws {
        // Si la vista se va en mitad de un fling y no llega a reanudar, la cola no puede
        // quedarse muerta con las imágenes de toda la app dentro. Se espera de verdad,
        // pero solo a que caduque: dormir de más no puede romperlo.
        let sut = DownloadQueue(limit: 1, pauseTimeout: .milliseconds(50))
        let order = OrderRecorder()

        await sut.setPaused(true)
        await enqueue(1, on: sut, recordingInto: order)

        #expect(await order.ids == [1])
        #expect(await sut.isPaused == false)
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
