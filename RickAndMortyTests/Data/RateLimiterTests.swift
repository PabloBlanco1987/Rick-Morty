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
        // saldría de ahí. El freno es compartido porque el límite también lo es.
        let sut = RateLimiter(coolOff: .milliseconds(80))

        await sut.reportRateLimited(retryAfter: nil)

        #expect(await sut.isCoolingOff)
    }

    @Test("The hold lifts on its own, and a success clears the record")
    func theHoldLiftsOnItsOwn() async throws {
        let sut = RateLimiter(coolOff: .milliseconds(50))
        await sut.reportRateLimited(retryAfter: nil)

        // La siguiente no falla: espera a que pase el freno y entra
        try await sut.acquire()
        await sut.reportSuccess()

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

    @Test("A 429 empties the bucket: nothing goes out until the hold lifts")
    func aRateLimitEmptiesTheBucket() async throws {
        let sut = RateLimiter(maxRate: 10, burst: 3, coolOff: .milliseconds(60))
        let clock = ContinuousClock()

        await sut.reportRateLimited(retryAfter: nil)
        let elapsed = try await clock.measure { try await sut.acquire() }

        // Ni la ráfaga sirve: se ha esperado el freno entero
        #expect(elapsed >= .milliseconds(50))
    }

    @Test("The disabled limiter never waits and never holds")
    func disabledDoesNothing() async throws {
        let sut = RateLimiter.disabled
        let clock = ContinuousClock()

        let elapsed = try await clock.measure {
            for _ in 0..<50 { try await sut.acquire() }
        }
        await sut.reportRateLimited(retryAfter: nil)

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
