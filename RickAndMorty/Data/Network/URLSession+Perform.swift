import Foundation

// Lo que devuelve una petición que ha llegado a contestar: los bytes, la respuesta cruda
// y lo que ha tardado la red, sin contar la espera por la ficha del limitador.
struct HTTPExchange: Sendable {
    let data: Data
    let response: HTTPURLResponse
    let duration: Duration
}

extension URLSession {
    // Una petición de verdad, de principio a fin: ficha del limitador, traza, transporte,
    // código de estado y aviso al limitador de cómo ha ido.
    //
    // Es lo que comparten las dos únicas salidas a la red de la app —el JSON de
    // URLSessionHTTPClient y las imágenes de ImageCache—, y vive aquí para que sea una
    // sola: antes eran dos copias línea a línea, y dos copias es la forma más fácil de
    // que dentro de un mes solo una sepa qué es un 429 o cuándo hay que avisar al
    // limitador. Lo que cada una hace con los bytes —decodificar un modelo, guardarlos en
    // disco— ya es cosa suya.
    func perform(
        _ request: URLRequest,
        through limiter: RateLimiter,
        logger: NetworkLogger = .shared
    ) async throws(AppError) -> HTTPExchange {
        // Antes de trazar y de arrancar el reloj: la espera por una ficha no es tiempo
        // de red, y en la traza lo que interesa es lo que tarda el servidor
        try await limiter.acquire()

        logger.logRequest(request)
        let start = ContinuousClock.now

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await self.data(for: request)
        } catch let error as URLError {
            logger.logFailure(error, for: request, duration: start.duration(to: .now))
            throw AppError(error)
        } catch let error where error is CancellationError {
            logger.logFailure(error, for: request, duration: start.duration(to: .now))
            throw .cancelled
        } catch {
            logger.logFailure(error, for: request, duration: start.duration(to: .now))
            throw .unknown
        }

        let elapsed = start.duration(to: .now)

        guard let http = response as? HTTPURLResponse else {
            logger.logFailure(AppError.unknown, for: request, duration: elapsed)
            throw .unknown
        }

        // Se traza antes de mirar el código de estado, para que un 404 o un 429 salgan
        // por consola tal cual llegaron, sin pasar por la traducción a AppError
        logger.logResponse(http, for: request, duration: elapsed)

        // El limitador se entera aquí y no en la traducción a AppError porque el
        // Retry-After va en la respuesta cruda, y esta es la única que lo tiene delante.
        // Y se le dice cuándo salió la petición: es lo que le deja distinguir un 429 de
        // la ráfaga que ya frenó de uno nuevo.
        if http.statusCode == 429 {
            await limiter.reportRateLimited(retryAfter: http.retryAfter, issuedAt: start)
        } else if (200..<300).contains(http.statusCode) {
            await limiter.reportSuccess(issuedAt: start)
        }

        if let error = AppError(statusCode: http.statusCode) { throw error }
        return HTTPExchange(data: data, response: http, duration: elapsed)
    }
}
