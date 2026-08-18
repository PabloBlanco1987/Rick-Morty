import Foundation
import Testing
@testable import RickAndMorty

// Serializada porque StubURLProtocol guarda estado a nivel de proceso: el registro
// de URLProtocol es global, así que dos de estas a la vez se contestarían las
// peticiones la una a la otra.
@Suite("URLSession HTTP client", .serialized)
struct URLSessionHTTPClientTests {
    private let sut = URLSessionHTTPClient(
        base: RickAndMortyAPI.base,
        session: StubURLProtocol.makeSession(),
        // Sin limitador: aquí se prueba la traducción de respuestas, no el ritmo, y el
        // test del 429 no puede dejar el freno puesto en el .shared del proceso
        limiter: .disabled
    )

    @Test("Decodes a success payload into the requested type")
    func decodesSuccess() async throws {
        StubURLProtocol.install(.ok(JSONFixtures.rick))

        let dto = try await sut.send(RickAndMortyAPI.character(id: 1), as: CharacterDTO.self)

        #expect(dto.id == 1)
        #expect(dto.name == "Rick Sanchez")
    }

    @Test("Sends the URL the endpoint described")
    func sendsTheBuiltURL() async throws {
        StubURLProtocol.install(.ok(JSONFixtures.charactersPage))

        _ = try await sut.send(
            RickAndMortyAPI.characters(page: 2, filter: CharacterFilter(status: .dead)),
            as: PageDTO<CharacterDTO>.self
        )

        let sent = try #require(StubURLProtocol.lastRequest?.url?.absoluteString)
        #expect(sent.contains("/character"))
        #expect(sent.contains("page=2"))
        #expect(sent.contains("status=dead"))
    }

    @Test("A refresh reaches the session asking to revalidate what it has cached")
    func aFreshListingRevalidates() async throws {
        // Es el último eslabón de la frescura: la política viaja en la petición y no en
        // la sesión, porque la misma sesión sirve de caché al navegar y revalida al
        // refrescar. Aquí se comprueba que llega hasta lo que de verdad sale.
        StubURLProtocol.install(.ok(JSONFixtures.charactersPage))

        _ = try await sut.send(RickAndMortyAPI.characters(page: 1, freshness: .fresh), as: PageDTO<CharacterDTO>.self)

        #expect(StubURLProtocol.lastRequest?.cachePolicy == .reloadRevalidatingCacheData)
    }

    @Test("Translates 404 into notFound, keeping the status code out of the domain")
    func mapsNotFound() async {
        StubURLProtocol.install(.status(404, json: JSONFixtures.notFoundError))

        await #expect(throws: AppError.notFound) {
            _ = try await sut.send(RickAndMortyAPI.character(id: 9_999), as: CharacterDTO.self)
        }
    }

    @Test("Carries the status code through for other failures", arguments: [500, 502, 400])
    func mapsServerErrors(statusCode: Int) async {
        StubURLProtocol.install(.status(statusCode))

        await #expect(throws: AppError.server(statusCode: statusCode)) {
            _ = try await sut.send(RickAndMortyAPI.character(id: 1), as: CharacterDTO.self)
        }
    }

    @Test("A 429 is rate limiting, not a server error")
    func mapsRateLimiting() async {
        // La API va detrás de Cloudflare y contesta esto en cuanto le pides varias
        // páginas seguidas, que es lo que pasa al hacer scroll rápido. Meterlo en
        // .server lo dejaba fuera de los reintentos y sacaba una pantalla de error por
        // algo que se arregla solo esperando.
        StubURLProtocol.install(.status(429, json: #"{ "title": "Error 1015: You are being rate limited" }"#))

        await #expect(throws: AppError.rateLimited) {
            _ = try await sut.send(RickAndMortyAPI.character(id: 1), as: CharacterDTO.self)
        }
    }

    @Test("A 429 tells the shared limiter to hold, for as long as the server says")
    func reportsRateLimitingToTheLimiter() async throws {
        // Es lo que hace que un 429 en el JSON frene también las imágenes, y al revés:
        // el freno es uno solo, y el Retry-After lo lee quien tiene la respuesta cruda
        // delante, que es este cliente.
        let limiter = RateLimiter(coolOff: .seconds(10))
        let sut = URLSessionHTTPClient(
            base: RickAndMortyAPI.base,
            session: StubURLProtocol.makeSession(),
            limiter: limiter
        )
        var stub = StubURLProtocol.Stub.status(429)
        stub.headers["Retry-After"] = "3"
        StubURLProtocol.install(stub)

        _ = try? await sut.send(RickAndMortyAPI.character(id: 1), as: CharacterDTO.self)

        // Acotado por los dos lados: ni los diez segundos de la base —el encabezado se
        // habría ignorado— ni nada muy por debajo de tres, que sería leerlo mal
        let remaining = try #require(await limiter.remainingCoolOff)
        #expect(remaining > .seconds(2))
        #expect(remaining <= .seconds(3))
        #expect(await limiter.currentRate == 4)
    }

    @Test("A success tells the limiter, which is how the rate recovers")
    func reportsSuccessToTheLimiter() async throws {
        // Con un ritmo alto para que la ficha que hay que esperar tras el 429 —el cubo se
        // vacía— cueste microsegundos y no un cuarto de segundo de reloj de verdad
        let limiter = RateLimiter(maxRate: 1_000, coolOff: .zero, recoveryStreak: 1)
        let sut = URLSessionHTTPClient(
            base: RickAndMortyAPI.base,
            session: StubURLProtocol.makeSession(),
            limiter: limiter
        )
        await limiter.reportRateLimited(retryAfter: nil)
        StubURLProtocol.install(.ok(JSONFixtures.rick))

        _ = try await sut.send(RickAndMortyAPI.character(id: 1), as: CharacterDTO.self)

        #expect(await limiter.currentRate == 501)
    }

    @Test("A failure that is not a 429 leaves the limiter alone: it says nothing about the pace")
    func otherFailuresDoNotTouchTheLimiter() async throws {
        // Un 500 es un tropiezo del servidor, no un aviso de que vamos deprisa: ni frena
        // ni baja el ritmo, y tampoco cuenta como acierto para recuperarlo
        let limiter = RateLimiter(maxRate: 1_000, coolOff: .zero, recoveryStreak: 1)
        let sut = URLSessionHTTPClient(
            base: RickAndMortyAPI.base,
            session: StubURLProtocol.makeSession(),
            limiter: limiter
        )
        await limiter.reportRateLimited(retryAfter: nil)
        StubURLProtocol.install(.status(500))

        _ = try? await sut.send(RickAndMortyAPI.character(id: 1), as: CharacterDTO.self)

        #expect(await limiter.currentRate == 500)
        #expect(await limiter.isCoolingOff == false)
    }

    @Test("A payload of the wrong shape is a decoding failure, not a crash")
    func mapsDecodingFailure() async {
        StubURLProtocol.install(.ok(#"{ "unexpected": true }"#))

        await #expect(throws: AppError.decoding) {
            _ = try await sut.send(RickAndMortyAPI.character(id: 1), as: CharacterDTO.self)
        }
    }

    @Test("Connectivity failures surface as offline", arguments: [
        URLError.Code.notConnectedToInternet,
        .networkConnectionLost,
        .dataNotAllowed,
        .cannotFindHost,
    ])
    func mapsOffline(code: URLError.Code) async {
        StubURLProtocol.install(.transport(code))

        await #expect(throws: AppError.offline) {
            _ = try await sut.send(RickAndMortyAPI.character(id: 1), as: CharacterDTO.self)
        }
    }

    @Test("A timeout is distinguishable from being offline")
    func mapsTimeout() async {
        StubURLProtocol.install(.transport(.timedOut))

        await #expect(throws: AppError.timeout) {
            _ = try await sut.send(RickAndMortyAPI.character(id: 1), as: CharacterDTO.self)
        }
    }

    @Test("Cancellation is its own case, never shown as an error to the user")
    func mapsCancellation() async {
        StubURLProtocol.install(.transport(.cancelled))

        await #expect(throws: AppError.cancelled) {
            _ = try await sut.send(RickAndMortyAPI.character(id: 1), as: CharacterDTO.self)
        }
    }
}
