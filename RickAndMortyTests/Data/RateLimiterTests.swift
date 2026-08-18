import Foundation
import Testing
@testable import RickAndMorty

// El limitador es la pieza que decide cuándo se sale a la red, así que lo que se prueba
// son decisiones: cuánto se retiene, a qué ritmo se vuelve y qué se hace con lo que dice
// el servidor. Donde hace falta un reloj de verdad —que una espera de fichas exista— se
// mide con márgenes que una máquina lenta solo puede agrandar, nunca romper.
@Suite("Rate limiter")
struct RateLimiterTests {
    // MARK: - El freno compartido

    @Test("A rate limited response puts every request on hold, not just its own")
    func aRateLimitHoldsEveryone() async throws {
        // Es lo que separa recuperarse de hundirse más: si cada imagen reintentase su
        // propio 429, el reintento repetiría la ráfaga que se ganó el límite y ya no se
        // saldría de ahí. El freno es compartido porque el límite también lo es: dos
        // peticiones que no tienen nada que ver con la que recibió el 429 esperan las dos.
        let sut = RateLimiter(coolOff: .milliseconds(80))
        let clock = ContinuousClock()

        await sut.reportRateLimited(retryAfter: nil)
        async let first = clock.measure { try await sut.acquire() }
        async let second = clock.measure { try await sut.acquire() }
        let (firstWait, secondWait) = try await (first, second)

        #expect(firstWait >= .milliseconds(70))
        #expect(secondWait >= .milliseconds(70))
    }

    @Test("The hold lifts on its own: the next request waits it out and goes through")
    func theHoldLiftsOnItsOwn() async throws {
        // Que la espera exista es lo que se mide; que termine, que acquire() vuelva. Que
        // un acierto borre la racha lo prueba aSuccessResetsTheEscalation.
        let sut = RateLimiter(coolOff: .milliseconds(50))
        await sut.reportRateLimited(retryAfter: nil)

        let waited = try await ContinuousClock().measure { try await sut.acquire() }

        #expect(waited >= .milliseconds(40))
        #expect(await sut.isCoolingOff == false)
    }

    @Test("Each consecutive 429 doubles the hold, up to eight times the base")
    func consecutiveRateLimitsDoubleTheHold() async {
        // Si el servidor sigue diciendo que no, insistir al mismo ritmo es alargar el
        // castigo. Y hay tope: sin él, una mala racha dejaría la app muda minutos.
        let sut = RateLimiter(coolOff: .seconds(10))

        await sut.reportRateLimited(retryAfter: nil)
        let first = await sut.remainingCoolOff
        await sut.reportRateLimited(retryAfter: nil)
        let second = await sut.remainingCoolOff
        for _ in 0..<5 { await sut.reportRateLimited(retryAfter: nil) }
        let capped = await sut.remainingCoolOff

        #expect(first.isAbout(.seconds(10)))
        #expect(second.isAbout(.seconds(20)))
        #expect(capped.isAbout(.seconds(80)))
    }

    @Test("A success in between resets the escalation")
    func aSuccessResetsTheEscalation() async {
        let sut = RateLimiter(coolOff: .seconds(10))

        await sut.reportRateLimited(retryAfter: nil)
        await sut.reportSuccess()
        await sut.reportRateLimited(retryAfter: nil)

        #expect(await sut.remainingCoolOff.isAbout(.seconds(10)))
    }

    @Test("When the server says how long to wait, that is what is waited")
    func honoursRetryAfter() async {
        // Cloudflare sabe mejor que nosotros cuánto queda de castigo. Con una base de
        // diez segundos, que la espera sea de uno solo puede venir del encabezado.
        let sut = RateLimiter(coolOff: .seconds(10))

        await sut.reportRateLimited(retryAfter: .seconds(1))

        #expect(await sut.remainingCoolOff.isAbout(.seconds(1)))
    }

    @Test("A Retry-After beyond reason is capped")
    func capsRetryAfter() async {
        // Un encabezado disparatado no puede dejar la app muda medio minuto sin más
        // razón que un número
        let sut = RateLimiter()

        await sut.reportRateLimited(retryAfter: .seconds(600))

        #expect(await sut.remainingCoolOff.isAbout(.seconds(30)))
    }

    @Test("Waiting out the hold can be cancelled")
    func cancellingWhileHeldThrowsCancelled() async {
        let sut = RateLimiter(coolOff: .seconds(60))
        await sut.reportRateLimited(retryAfter: nil)

        let waiting = Task { try await sut.acquire() }
        waiting.cancel()

        await #expect(throws: AppError.cancelled) { try await waiting.value }
    }

    // MARK: - Lo que salió antes del freno no cuenta

    @Test("A 429 from a request that was already in flight when the hold started does not escalate it")
    func aRateLimitFromBeforeTheHoldDoesNotCount() async {
        // Cuando Cloudflare corta, los cuatro huecos de imágenes y la página en vuelo
        // contestan 429 casi a la vez. Contados uno a uno, un solo aviso del servidor
        // dejaba el freno en ocho veces la base y el ritmo en el suelo. Todo lo que
        // salió antes de ponerse el freno pertenece a la misma ráfaga: el primero lo pone
        // y los demás no añaden nada.
        let sut = RateLimiter(maxRate: 8, coolOff: .seconds(10))
        let issuedBeforeTheHold = ContinuousClock.now

        await sut.reportRateLimited(retryAfter: nil)
        await sut.reportRateLimited(retryAfter: nil, issuedAt: issuedBeforeTheHold)
        await sut.reportRateLimited(retryAfter: nil, issuedAt: issuedBeforeTheHold)

        #expect(await sut.remainingCoolOff.isAbout(.seconds(10)))
        #expect(await sut.currentRate == 4)
    }

    @Test("A success from before the hold says nothing about now: it neither resets the count nor recovers rate")
    func aSuccessFromBeforeTheHoldDoesNotCount() async {
        // Una petición que salió antes del freno y contestó bien habla de cómo estaba el
        // servidor antes de decir que no, no de cómo está ahora. Si borrase la racha, el
        // siguiente 429 volvería a la espera base y el freno no escalaría nunca.
        let sut = RateLimiter(maxRate: 8, coolOff: .seconds(10), recoveryStreak: 1)
        let issuedBeforeTheHold = ContinuousClock.now

        await sut.reportRateLimited(retryAfter: nil)
        await sut.reportSuccess(issuedAt: issuedBeforeTheHold)
        #expect(await sut.currentRate == 4)

        await sut.reportRateLimited(retryAfter: nil)

        // Si el acierto viejo hubiera contado, este sería el primer 429 de una racha
        // nueva y la espera volvería a ser la base; que la escalación siga es la prueba
        // de que no ha contado. El caso contrario —un acierto de después sí recupera
        // ritmo— ya lo cubre adaptsTheRate.
        #expect(await sut.remainingCoolOff.isAbout(.seconds(20)))
    }

    // MARK: - El ritmo adaptativo

    @Test("A 429 halves the rate, down to a floor; successes bring it back one step at a time")
    func adaptsTheRate() async {
        // Baja a la mitad y sube de uno en uno: es más barato equivocarse por lento que
        // volver a ganarse el freno. Y el suelo evita que una mala racha deje el ritmo
        // en cero, que sería no volver a pedir nunca.
        let sut = RateLimiter(maxRate: 8, minRate: 2, coolOff: .zero, recoveryStreak: 3)

        await sut.reportRateLimited(retryAfter: nil)
        #expect(await sut.currentRate == 4)
        await sut.reportRateLimited(retryAfter: nil)
        #expect(await sut.currentRate == 2)
        await sut.reportRateLimited(retryAfter: nil)
        #expect(await sut.currentRate == 2)

        for _ in 0..<3 { await sut.reportSuccess() }
        #expect(await sut.currentRate == 3)
        for _ in 0..<2 { await sut.reportSuccess() }
        #expect(await sut.currentRate == 3)
        await sut.reportSuccess()
        #expect(await sut.currentRate == 4)
    }

    @Test("A 429 wipes a recovery streak in progress: the climb starts over")
    func aRateLimitResetsThePartialStreak() async {
        // Dos aciertos de tres no son ritmo ganado hasta que llega el tercero, y un 429
        // entre medias los borra: si contaran, el primer acierto de después subiría el
        // ritmo justo cuando el servidor acaba de pedir lo contrario
        let sut = RateLimiter(maxRate: 8, minRate: 2, coolOff: .zero, recoveryStreak: 3)
        await sut.reportRateLimited(retryAfter: nil)
        for _ in 0..<2 { await sut.reportSuccess() }

        await sut.reportRateLimited(retryAfter: nil)
        await sut.reportSuccess()

        #expect(await sut.currentRate == 2)
        for _ in 0..<2 { await sut.reportSuccess() }
        #expect(await sut.currentRate == 3)
    }

    @Test("The rate never climbs past the maximum")
    func doesNotExceedTheMaximum() async {
        let sut = RateLimiter(maxRate: 8, recoveryStreak: 1)

        for _ in 0..<10 { await sut.reportSuccess() }

        #expect(await sut.currentRate == 8)
    }

    // MARK: - El cubo de fichas

    @Test("Requests within the burst go straight through; the next one waits for a token")
    func spacesRequestsBeyondTheBurst() async throws {
        // Diez fichas por segundo con tres de ráfaga: las tres primeras salen ya y la
        // cuarta tiene que esperar a que se genere una, unos cien milisegundos. Es la
        // diferencia entre limitar cuántas van a la vez y limitar cuántas salen por
        // segundo, que es lo que cuenta el servidor.
        let sut = RateLimiter(maxRate: 10, burst: 3)
        let clock = ContinuousClock()

        let burst = try await clock.measure {
            for _ in 0..<3 { try await sut.acquire() }
        }
        let fourth = try await clock.measure {
            try await sut.acquire()
        }

        // Una máquina lenta solo puede alargar la cuarta, y ni la más lenta tarda medio
        // segundo en tres llamadas que no esperan a nada
        #expect(burst < .milliseconds(500))
        #expect(fourth >= .milliseconds(80))
    }

    @Test("A 429 empties the bucket and keeps it empty through the hold, so nothing bursts out when it lifts")
    func theBucketStaysEmptyThroughTheHold() async throws {
        // Ni la ráfaga que quedaba sirve, ni se acumula otra mientras dura el freno: si el
        // cubo se llenara mientras tanto, al levantarse saldría una ráfaga entera de golpe,
        // que es justo lo que acaba de decir el servidor que no quiere.
        // Con el ritmo ya a la mitad —diez por segundo— y el cubo vacío, tres peticiones
        // seguidas son el freno más tres fichas de cien milisegundos: medio segundo. Si el
        // cubo se llenara durante el freno, dos de las tres saldrían nada más levantarse y
        // el total no pasaría de 300 ms.
        let sut = RateLimiter(maxRate: 20, burst: 3, coolOff: .milliseconds(200))
        let clock = ContinuousClock()

        await sut.reportRateLimited(retryAfter: nil)
        let elapsed = try await clock.measure {
            for _ in 0..<3 { try await sut.acquire() }
        }

        // Una máquina lenta solo puede alargar la espera, nunca acortarla
        #expect(elapsed >= .milliseconds(450))
    }

    @Test("Waiting for a token can be cancelled too")
    func cancellingWhileWaitingForATokenThrowsCancelled() async throws {
        // Es el otro sitio donde acquire() duerme. Una celda que se va mientras espera
        // ficha no puede quedarse aparcada hasta que le toque, ni salir a la red cuando
        // le toque: quien esperaba ya no quiere salir.
        let sut = RateLimiter(maxRate: 1, burst: 1)
        try await sut.acquire()

        let waiting = Task { try await sut.acquire() }
        waiting.cancel()

        await #expect(throws: AppError.cancelled) { try await waiting.value }
    }

    @Test("The disabled limiter never waits and never holds, whatever the server says")
    func disabledDoesNothing() async throws {
        // Es el que usan los tests del cliente HTTP y las previews: un 429 con
        // Retry-After no puede dejar el freno puesto para el siguiente
        let sut = RateLimiter.disabled
        let clock = ContinuousClock()

        let elapsed = try await clock.measure {
            for _ in 0..<50 { try await sut.acquire() }
        }
        await sut.reportRateLimited(retryAfter: .seconds(30))

        #expect(elapsed < .milliseconds(500))
        #expect(await sut.isCoolingOff == false)
    }
}

@Suite("Retry-After header")
struct RetryAfterHeaderTests {
    @Test("Seconds are read as a duration", arguments: [("7", Duration.seconds(7)), (" 12 ", .seconds(12))])
    func readsSeconds(raw: String, expected: Duration) throws {
        #expect(try response(retryAfter: raw).retryAfter == expected)
    }

    @Test(
        "Missing, zero or a date give nothing to wait for",
        arguments: [nil, "0", "-3", "Wed, 21 Oct 2015 07:28:00 GMT"]
    )
    func ignoresWhatIsNotAPositiveNumber(raw: String?) throws {
        // La forma con fecha se ignora a propósito: Cloudflare no la usa y parsearla
        // sería más código que valor. Sin dato, el limitador usa su propia espera.
        #expect(try response(retryAfter: raw).retryAfter == nil)
    }

    private func response(retryAfter: String?) throws -> HTTPURLResponse {
        try #require(HTTPURLResponse(
            url: URL(filePath: "/api/character"),
            statusCode: 429,
            httpVersion: "HTTP/1.1",
            headerFields: retryAfter.map { ["Retry-After": $0] }
        ))
    }
}

private extension Optional where Wrapped == Duration {
    // Lo que queda de un freno recién puesto: el objetivo menos los microsegundos que
    // haya tardado en llegar la comprobación. Un segundo de margen sobra en cualquier
    // máquina y sigue distinguiendo diez de veinte.
    func isAbout(_ target: Duration) -> Bool {
        guard let self else { return false }
        return self > target - .seconds(1) && self <= target
    }
}
