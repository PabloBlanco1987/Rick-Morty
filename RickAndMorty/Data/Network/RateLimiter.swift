import Foundation

// El ritmo al que la app se permite salir a la red, para todo el host a la vez.
//
// La API va detrás de Cloudflare, que limita por IP y antes de su caché: cada página de
// JSON y cada avatar cuentan contra el mismo cupo, y el 429 lo pone él, no el servidor.
// Hasta ahora la app limitaba cuántas descargas iban a la vez, pero no cuántas salían por
// segundo, y cuatro imágenes de 40 KB a 150 ms son veinticinco peticiones por segundo:
// justo la ráfaga que se gana el castigo. Y el JSON y las imágenes se frenaban cada uno
// por su lado, así que cuando las imágenes provocaban el 429 la página siguiente también
// se lo comía sin haber hecho nada.
//
// Por eso es una sola pieza compartida, con dos mecanismos:
//
// - Un cubo de fichas (token bucket): `rate` fichas por segundo hasta `burst` acumuladas.
//   Cada petición gasta una; sin fichas se espera. Es lo que convierte "reaccionar al
//   castigo" en "no ganárselo".
// - Un freno compartido cuando aun así llega un 429: nadie sale hasta que pase el
//   `Retry-After` que diga el servidor o, si no lo dice, una espera que se dobla con cada
//   429 seguido. Y el ritmo se baja a la mitad; con cada racha de aciertos se recupera un
//   poco. Es control de congestión: no sabemos qué umbral tiene puesto Cloudflare, así que
//   el ritmo se calibra solo contra lo que el servidor va contestando.
//
// Es un actor porque lo tocan a la vez las descargas de imágenes y el cliente HTTP, y el
// estado que protege —fichas, freno, ritmo— tiene que ser uno solo para que el freno sea
// de verdad compartido.
actor RateLimiter {
    static let shared = RateLimiter()

    // Sin ritmo ni freno, para los tests que prueban otra cosa y no deben esperar a
    // nadie. Es una propiedad calculada a propósito: cada acceso da una instancia nueva,
    // así que un test que provoque un 429 no deja el freno puesto para el siguiente.
    static var disabled: RateLimiter {
        RateLimiter(maxRate: .infinity, burst: .infinity, coolOff: .zero)
    }

    private let maxRate: Double
    private let minRate: Double
    private let burst: Double
    private let coolOff: Duration
    private let recoveryStreak: Int
    private let logger = NetworkLogger.shared

    // Lo que dura como mucho un Retry-After. Un valor disparatado del servidor no puede
    // dejar la app muda medio minuto sin más razón que un encabezado.
    private static let maxRetryAfter: Duration = .seconds(30)

    private var rate: Double
    private var tokens: Double
    private var lastRefill: ContinuousClock.Instant

    // Hasta cuándo hay que dejar de pedir, y cuántos 429 seguidos llevamos
    private var coolOffUntil: ContinuousClock.Instant?
    private var consecutiveRateLimits = 0
    private var successStreak = 0

    // Cuándo se puso el último freno. Es lo que separa "otro 429" de "el mismo 429": lo
    // que ya estaba en vuelo cuando se puso el freno pertenece a la ráfaga que lo
    // provocó, y no puede contar como una racha nueva
    private var holdStartedAt: ContinuousClock.Instant?

    // internal para que los tests puedan comprobar el freno y el ritmo sin mirar el reloj
    var isCoolingOff: Bool { remainingCoolOff != nil }
    var currentRate: Double { rate }

    var remainingCoolOff: Duration? {
        guard let coolOffUntil else { return nil }
        let remaining = ContinuousClock.now.duration(to: coolOffUntil)
        return remaining > .zero ? remaining : nil
    }

    // Los valores por defecto son un punto de partida, no una medida: el umbral de
    // Cloudflare no está documentado, así que se empieza prudente y el ritmo se ajusta
    // solo. Ocho por segundo llenan la pantalla donde aterriza un fling en menos de un
    // segundo y calientan una página de veinte en dos y medio; leyendo, sobra.
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

    // Espera a que se pueda salir a la red y gasta una ficha. Se llama justo antes de
    // cada petición de verdad, en los dos únicos sitios donde se hacen: el cliente HTTP y
    // la descarga de imágenes.
    //
    // Es un bucle y no una cola de espera a propósito: como mucho esperan aquí cinco
    // tareas a la vez —los cuatro huecos de la cola de imágenes y la página en vuelo—, y
    // con tan pocas, dormir lo que falte y volver a mirar es más simple y da igual de
    // justo. El orden lo pone la cola de descargas, que es LIFO; aquí solo se raciona.
    func acquire() async throws(AppError) {
        while true {
            if let remaining = remainingCoolOff {
                try await sleep(remaining)
                continue
            }

            // Sin ritmo (tests) no hay fichas que contar. Y hay que salir antes de tocar
            // los números: infinito por cero es NaN.
            guard rate.isFinite else { return }

            refill()
            if tokens >= 1 {
                tokens -= 1
                return
            }
            try await sleep(.seconds((1 - tokens) / rate))
        }
    }

    // El servidor ha dicho que vamos demasiado rápido. Se para todo el mundo y se baja el
    // ritmo: reintentar al mismo paso sería alargar el castigo.
    //
    // issuedAt es cuándo salió la petición que ha recibido el 429 —quien llama lo toma
    // justo después de acquire()— y es lo que evita contar una ráfaga como una racha.
    // Cuando Cloudflare corta, los cuatro huecos de imágenes y la página en vuelo
    // contestan 429 casi a la vez; contados uno a uno, un solo aviso del servidor dejaba
    // el freno en dieciséis segundos y el ritmo en el suelo, y hacían falta ciento
    // ochenta aciertos para recuperarlo. Como acquire() no deja salir nada mientras dura
    // el freno, todo lo que salió antes de ponerlo pertenece a la ráfaga que lo provocó:
    // el primero pone el freno y los demás no añaden nada. Solo un 429 de una petición
    // que salió después —o sea, cuando ya se había levantado— cuenta como "otra vez".
    // Es lo mismo que hace TCP: baja a la mitad una vez por pérdida, no por paquete.
    func reportRateLimited(retryAfter: Duration?, issuedAt: ContinuousClock.Instant = .now) {
        // Sin ritmo (tests y previews) tampoco hay freno, diga lo que diga la cabecera
        guard rate.isFinite else { return }
        if let holdStartedAt, issuedAt < holdStartedAt { return }

        consecutiveRateLimits += 1
        successStreak = 0

        // Cada 429 seguido dobla la espera, hasta ocho veces la base. Si el servidor dice
        // cuánto, manda él.
        let backoff = coolOff * (1 << min(consecutiveRateLimits - 1, 3))
        let hold = retryAfter.map { min($0, Self.maxRetryAfter) } ?? backoff
        let now = ContinuousClock.now
        let until = now.advanced(by: hold)
        coolOffUntil = until
        holdStartedAt = now

        // El cubo se vacía y no empieza a llenarse hasta que pase el freno: si se
        // llenara mientras tanto, al levantarse saldría una ráfaga entera de golpe,
        // que es justo lo que acaba de decir el servidor que no quiere.
        tokens = 0
        lastRefill = until

        let previous = rate
        rate = max(minRate, rate / 2)
        logger.logThrottle("⏳ Rate limited · hold \(hold) · rate \(previous)→\(rate) req/s")
    }

    // Un acierto reinicia la cuenta de 429 seguidos y, cada tantos, devuelve un poco de
    // ritmo. Sube de uno en uno y baja a la mitad: es más barato equivocarse por lento
    // que volver a ganarse el freno.
    //
    // Con el mismo issuedAt que arriba y por la misma razón: un acierto de una petición
    // que ya estaba en vuelo cuando se puso el freno no dice nada de cómo está el
    // servidor ahora, así que ni borra la racha de 429 ni cuenta para recuperar ritmo.
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

    // MARK: - Fichas

    private func refill() {
        let now = ContinuousClock.now
        // lastRefill puede estar en el futuro justo después de un 429: hasta entonces
        // no hay nada que añadir
        guard now > lastRefill else { return }
        let elapsed = lastRefill.duration(to: now)
        lastRefill = now
        tokens = min(burst, tokens + Self.seconds(elapsed) * rate)
    }

    private func sleep(_ duration: Duration) async throws(AppError) {
        do {
            try await Task.sleep(for: duration)
        } catch {
            // Si sleep lanza es porque han cancelado: quien esperaba ya no quiere salir
            throw .cancelled
        }
    }

    private static func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) * 1e-18
    }
}

extension HTTPURLResponse {
    // El Retry-After de un 429, si viene y viene en segundos. La forma con fecha se
    // ignora: Cloudflare no la usa y parsearla es más código que valor.
    var retryAfter: Duration? {
        guard let raw = value(forHTTPHeaderField: "Retry-After")?
                .trimmingCharacters(in: .whitespaces),
              let seconds = Int(raw), seconds > 0
        else { return nil }
        return .seconds(seconds)
    }
}
