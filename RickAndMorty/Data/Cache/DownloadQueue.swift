import Foundation

// Cola de descargas con hueco limitado y orden LIFO.
//
// Las dos decisiones son por el scroll rápido, y las dos van contra el mismo error de
// bulto: creer que pedirlo todo a la vez es pedirlo antes.
//
// - Hueco limitado. URLSession abre seis conexiones por host, así que soltarle cien
//   imágenes de golpe no las trae antes: las pone en una cola que además es suya y no
//   se puede tocar. Con un tope propio la cola es nuestra y, sobre todo, se puede
//   ordenar.
// - LIFO. Cuando se libera un hueco entra la última imagen pedida, no la primera. Al
//   bajar rápido, la última pedida es la que el usuario tiene delante; la primera es
//   una que dejó atrás diez pantallas antes. En FIFO el usuario ve pintarse en orden
//   todas las que ya no mira antes de que le llegue la suya, que es exactamente la
//   sensación de que tarda muchísimo aunque el ancho de banda esté al máximo.
//
// Hace falta porque no se puede confiar en que la vista se destruya: LazyVGrid crea
// las celdas según hacen falta pero no las tira al pasar de largo, así que sus tareas
// siguen vivas y esperando. Ordenar la cola es lo único que queda.
actor DownloadQueue {
    typealias Work = () async throws(AppError) -> Data

    private let limit: Int
    private let coolOff: Duration
    private var running = 0
    private var waiting: [Ticket] = []
    private var lastTicketID = 0

    // Hasta cuándo hay que dejar de pedir, y cuántos 429 seguidos llevamos
    private var coolOffUntil: ContinuousClock.Instant?
    private var consecutiveRateLimits = 0

    private struct Ticket {
        let id: Int
        // Bool y no Void: dice si se ha conseguido el hueco o si han cancelado la
        // espera, que es lo que distingue quién tiene que devolverlo después
        let continuation: CheckedContinuation<Bool, Never>
    }

    // internal para que los tests puedan comprobar que la cola se vacía en vez de
    // acumular esperas que no van a ninguna parte
    var waitingCount: Int { waiting.count }
    var isCoolingOff: Bool { remainingCoolOff != nil }

    init(limit: Int = 4, coolOff: Duration = .seconds(2)) {
        self.limit = max(1, limit)
        self.coolOff = coolOff
    }

    func enqueue(_ work: Work) async throws(AppError) -> Data {
        // Cuando el servidor contesta 429 lo que hay que hacer no es reintentar: es
        // dejar de pedir. Si cada imagen reintenta por su cuenta, el reintento
        // multiplica exactamente la ráfaga que se ganó el 429 y ya no se sale de ahí:
        // más peticiones, más 429, más reintentos. El freno es compartido a propósito,
        // porque el límite también lo es.
        try await waitOutCoolOff()

        let granted = await acquire()
        // Solo devuelve el hueco quien lo cogió. A quien le cancelaron la espera nunca
        // llegó a ocupar uno.
        defer { if granted { release() } }

        do {
            let data = try await work()
            consecutiveRateLimits = 0
            return data
        } catch {
            if error == .rateLimited { startCoolOff() }
            throw error
        }
    }

    private func waitOutCoolOff() async throws(AppError) {
        while let remaining = remainingCoolOff {
            do {
                try await Task.sleep(for: remaining)
            } catch {
                throw .cancelled
            }
        }
    }

    private var remainingCoolOff: Duration? {
        guard let coolOffUntil else { return nil }
        let remaining = ContinuousClock.now.duration(to: coolOffUntil)
        return remaining > .zero ? remaining : nil
    }

    // Cada 429 seguido dobla la espera, hasta ocho veces la base. Si el servidor sigue
    // diciendo que no, insistir al mismo ritmo es alargar el castigo; un acierto la
    // devuelve al principio.
    private func startCoolOff() {
        consecutiveRateLimits += 1
        let factor = 1 << min(consecutiveRateLimits - 1, 3)
        coolOffUntil = ContinuousClock.now.advanced(by: coolOff * factor)
    }

    private func acquire() async -> Bool {
        if running < limit {
            running += 1
            return true
        }

        lastTicketID += 1
        let id = lastTicketID

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                waiting.append(Ticket(id: id, continuation: continuation))
            }
        } onCancel: {
            // Sin esto, a una celda cancelada mientras esperaba no la despierta nadie:
            // con LIFO su turno no llega nunca, porque siempre hay alguien más nuevo
            // por delante. La tarea se quedaría aparcada para siempre.
            Task { await self.abandon(id) }
        }
    }

    private func release() {
        guard let ticket = waiting.popLast() else {
            running -= 1
            return
        }
        // El hueco no se libera, se traspasa: así no hay una ventana en la que otro
        // pueda colarse por delante del que ya estaba esperando
        ticket.continuation.resume(returning: true)
    }

    private func abandon(_ id: Int) {
        guard let index = waiting.firstIndex(where: { $0.id == id }) else { return }
        waiting.remove(at: index).continuation.resume(returning: false)
    }
}
