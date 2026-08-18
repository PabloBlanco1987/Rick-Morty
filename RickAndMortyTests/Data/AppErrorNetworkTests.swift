import Foundation
import Testing
@testable import RickAndMorty

// La tabla que convierte lo que devuelve URLSession en AppError. Se prueba aparte del
// cliente HTTP porque la comparten dos salidas a la red —el JSON y las imágenes— y lo que
// importa es que la tabla sea una y esté completa: los tests del cliente comprueban que
// la usa; estos, qué dice.
@Suite("App error network translation")
struct AppErrorNetworkTests {
    @Test(
        "Anything that means 'no way to reach the server' is offline",
        arguments: [
            URLError.Code.notConnectedToInternet,
            .networkConnectionLost,
            .dataNotAllowed,
            .internationalRoamingOff,
            .cannotConnectToHost,
            .cannotFindHost,
            .dnsLookupFailed,
        ]
    )
    func connectivityFailuresAreOffline(code: URLError.Code) {
        // Para el usuario la instrucción es la misma en los siete casos —comprobar la
        // conexión y volver a intentarlo—, y reintentar solo no arregla ninguno
        #expect(AppError(URLError(code)) == .offline)
    }

    @Test("A timeout and a cancellation keep their own case")
    func timeoutAndCancellationAreDistinct() {
        // El timeout se reintenta solo y la cancelación no se enseña nunca: si cayeran
        // en el mismo saco que "sin conexión" se perdería una decisión en cada uno
        #expect(AppError(URLError(.timedOut)) == .timeout)
        #expect(AppError(URLError(.cancelled)) == .cancelled)
    }

    @Test(
        "Everything else is unknown rather than guessed",
        arguments: [URLError.Code.badURL, .badServerResponse, .secureConnectionFailed, .httpTooManyRedirects]
    )
    func otherTransportFailuresAreUnknown(code: URLError.Code) {
        #expect(AppError(URLError(code)) == .unknown)
    }

    @Test("A 2xx has nothing to translate", arguments: [200, 201, 204, 299])
    func successCodesTranslateToNothing(statusCode: Int) {
        // nil y no un caso de éxito: quien llama sigue con los bytes, y no hay un
        // AppError.success que alguien pudiera lanzar por error
        #expect(AppError(statusCode: statusCode) == nil)
    }

    @Test("404 and 429 are the two codes the app treats specially")
    func notFoundAndRateLimitedHaveTheirOwnCase() {
        // El 404 es lo que la API contesta a una búsqueda sin resultados, y el 429 lo
        // pone Cloudflare al hacer scroll rápido: los dos necesitan una reacción propia,
        // no un mensaje de "error del servidor"
        #expect(AppError(statusCode: 404) == .notFound)
        #expect(AppError(statusCode: 429) == .rateLimited)
    }

    @Test("Any other status keeps its code", arguments: [400, 401, 403, 500, 502, 503])
    func otherStatusesKeepTheirCode(statusCode: Int) {
        // Se conserva el código porque de él depende si merece reintento: un 5xx sí,
        // un 4xx no
        #expect(AppError(statusCode: statusCode) == .server(statusCode: statusCode))
    }
}
