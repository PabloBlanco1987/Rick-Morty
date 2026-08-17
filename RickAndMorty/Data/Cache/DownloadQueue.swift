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
//
// Aquí solo se reparten huecos. Cuántas peticiones por segundo pueden salir, y el freno
// cuando el servidor contesta 429, viven en RateLimiter: ese límite lo comparten las
// imágenes con el JSON, así que no puede estar dentro de la cola de una de las dos.
actor DownloadQueue {
    typealias Work = () async throws(AppError) -> Data

    // Quién pide el hueco. Una celda que se está viendo va delante de todo; un
    // precalentamiento —imágenes de la página que acaba de llegar y aún no se ve— solo
    // entra cuando no espera nada visible.
    enum Priority: Sendable {
        case visible
        case prefetch
    }

    private let limit: Int
    private let pauseTimeout: Duration
    private var running = 0
    private var waiting: [Ticket] = []
    private var lastTicketID = 0

    // En pausa no se conceden huecos nuevos. Lo pone la vista mientras el scroll va
    // lanzado —ver CharacterListView— y lo quita cuando para. Y caduca solo: si la vista
    // se destruye en mitad de un fling y no llega a quitarlo, la cola no puede quedarse
    // muerta con las imágenes de toda la app dentro.
    private(set) var isPaused = false
    private var pauseGeneration = 0

    private struct Ticket {
        let id: Int
        // Bool y no Void: dice si se ha conseguido el hueco o si han cancelado la
        // espera, que es lo que distingue quién tiene que devolverlo después
        let continuation: CheckedContinuation<Bool, Never>
    }

    // internal para que los tests puedan comprobar que la cola se vacía en vez de
    // acumular esperas que no van a ninguna parte
    var waitingCount: Int { waiting.count }

    init(limit: Int = 4, pauseTimeout: Duration = .seconds(1.5)) {
        self.limit = max(1, limit)
        self.pauseTimeout = pauseTimeout
    }

    func enqueue(priority: Priority = .visible, _ work: Work) async throws(AppError) -> Data {
        let granted = await acquire(priority)
        // A quien le cancelaron la espera nunca llegó a ocupar un hueco: ni se ejecuta
        // su trabajo ni tiene nada que devolver.
        guard granted else { throw .cancelled }
        defer { release() }

        return try await work()
    }

    // MARK: - Pausa

    func setPaused(_ paused: Bool) {
        guard paused != isPaused else { return }
        isPaused = paused
        pauseGeneration += 1

        if paused {
            let generation = pauseGeneration
            // La tarea hereda el aislamiento del actor: dormir no lo bloquea, y al
            // despertar sigue dentro, así que expirePause se llama sin salto
            Task {
                try? await Task.sleep(for: pauseTimeout)
                expirePause(generation)
            }
        } else {
            grantWhilePossible()
        }
    }

    // La generación evita que un temporizador viejo levante una pausa nueva: pausar,
    // reanudar y volver a pausar deja un temporizador de la primera que ya no manda.
    private func expirePause(_ generation: Int) {
        guard isPaused, pauseGeneration == generation else { return }
        isPaused = false
        grantWhilePossible()
    }

    private func grantWhilePossible() {
        while running < limit, let ticket = waiting.popLast() {
            running += 1
            ticket.continuation.resume(returning: true)
        }
    }

    // MARK: - Huecos

    private func acquire(_ priority: Priority) async -> Bool {
        if !isPaused, running < limit {
            running += 1
            return true
        }

        lastTicketID += 1
        let id = lastTicketID

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let ticket = Ticket(id: id, continuation: continuation)
                switch priority {
                case .visible:
                    // Al final, que es de donde sale el siguiente: LIFO entre lo visible
                    waiting.append(ticket)
                case .prefetch:
                    // Al principio, que es de donde no sale nada mientras haya otra
                    // cosa: solo entra cuando no espera nada visible
                    waiting.insert(ticket, at: 0)
                }
            }
        } onCancel: {
            // Sin esto, a una celda cancelada mientras esperaba no la despierta nadie:
            // con LIFO su turno no llega nunca, porque siempre hay alguien más nuevo
            // por delante. La tarea se quedaría aparcada para siempre.
            Task { await self.abandon(id) }
        }
    }

    private func release() {
        // En pausa el hueco se devuelve y no se traspasa: es la única forma de que dejen
        // de salir peticiones. Al reanudar, grantWhilePossible los vuelve a repartir.
        guard !isPaused, let ticket = waiting.popLast() else {
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
