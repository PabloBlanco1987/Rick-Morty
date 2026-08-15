import Foundation

// Un pestillo asíncrono: quien llama a wait() se queda parado hasta que el test abre.
//
// Sirve para congelar una operación en vuelo y comprobar qué hace la app mientras
// tanto. La alternativa —dormir 50 ms y confiar— es la receta habitual de los tests
// que fallan una vez de cada treinta en la máquina de integración, así que aquí no hay
// tiempos: hay rendezvous.
actor AsyncGate {
    private var isOpen = false
    private var hasBeenReached = false
    private var blocked: [CheckedContinuation<Void, Never>] = []
    private var watchers: [CheckedContinuation<Void, Never>] = []

    // La llama el código bajo prueba
    func wait() async {
        hasBeenReached = true
        watchers.forEach { $0.resume() }
        watchers.removeAll()

        guard !isOpen else { return }
        await withCheckedContinuation { blocked.append($0) }
    }

    // La llama el test: vuelve en cuanto alguien ha llegado al pestillo, así que a
    // partir de ahí se sabe con certeza que la operación está congelada dentro
    func waitUntilReached() async {
        guard !hasBeenReached else { return }
        await withCheckedContinuation { watchers.append($0) }
    }

    // Abre y deja abierto: quien llegue después ya no se para
    func open() {
        isOpen = true
        blocked.forEach { $0.resume() }
        blocked.removeAll()
    }
}

// Apunta las esperas en vez de dormirlas de verdad, así lo que se comprueba es la
// decisión —cuánto se decide esperar y cuándo— y no el reloj, y la suite entera se
// queda en milisegundos
actor SleepRecorder {
    private(set) var durations: [Duration] = []

    func record(_ duration: Duration) { durations.append(duration) }
}

// Apunta el orden en el que se ha ido atendiendo cada petición
actor OrderRecorder {
    private(set) var ids: [Int] = []

    func record(_ id: Int) { ids.append(id) }
}

// Cuántas cosas han llegado a estar en marcha a la vez. Es lo que distingue un límite
// que se respeta de uno que solo está escrito.
actor ConcurrencyProbe {
    private(set) var current = 0
    private(set) var peak = 0

    func enter() {
        current += 1
        peak = max(peak, current)
    }

    func leave() { current -= 1 }
}
