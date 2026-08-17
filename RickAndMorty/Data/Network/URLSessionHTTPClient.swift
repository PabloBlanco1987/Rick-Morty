import Foundation

// El único sitio de la app que habla con la red.
// Todo lo que puede fallar (transporte, código de estado, payload roto) se traduce a
// AppError antes de salir de aquí, así que URLError y DecodingError no se escapan
// nunca de la capa de datos.
struct URLSessionHTTPClient: HTTPClient {
    private let base: URLComponents
    private let session: URLSession
    private let logger: NetworkLogger
    private let limiter: RateLimiter

    init(
        base: URLComponents = RickAndMortyAPI.base,
        session: URLSession = .rickAndMorty,
        logger: NetworkLogger = .shared,
        // El mismo que usa la caché de imágenes: el cupo del servidor es uno para JSON
        // e imágenes, así que el freno tiene que ser el mismo objeto
        limiter: RateLimiter = .shared
    ) {
        self.base = base
        self.session = session
        self.logger = logger
        self.limiter = limiter
    }

    func send<Response: Decodable & Sendable>(
        _ endpoint: Endpoint,
        as type: Response.Type
    ) async throws(AppError) -> Response {
        guard let request = endpoint.urlRequest(base: base) else {
            throw .unknown
        }

        // Antes de trazar y de arrancar el reloj: la espera por una ficha no es tiempo
        // de red, y en la traza lo que interesa es lo que tarda el servidor
        try await limiter.acquire()

        logger.logRequest(request)
        let start = ContinuousClock.now

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
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
        // Retry-After va en la respuesta cruda, y esta es la única que lo tiene delante
        if http.statusCode == 429 {
            await limiter.reportRateLimited(retryAfter: http.retryAfter)
        } else if (200..<300).contains(http.statusCode) {
            await limiter.reportSuccess()
        }

        if let error = AppError(statusCode: http.statusCode) { throw error }

        do {
            // JSONDecoder no es Sendable, así que lo creo en cada llamada en vez de
            // guardarlo. Crearlo cuesta microsegundos frente a una petición de
            // decenas de milisegundos: no compensa un @unchecked Sendable.
            return try JSONDecoder.rickAndMorty.decode(Response.self, from: data)
        } catch {
            // El DecodingError trae la ruta exacta de la clave que no cuadra, y al salir
            // de aquí como .decoding se pierde. Es la única traza que lo cuenta.
            logger.logFailure(error, for: request, duration: elapsed)
            throw .decoding
        }
    }
}

extension URLSession {
    // La sesión con la que va la app.
    // Toda la caché de respuestas es este URLCache privado: la API manda ETag y
    // Cache-Control, y con .useProtocolCachePolicy una página ya vista se revalida
    // con una petición condicional (un 304 sin cuerpo) o sale directamente de disco.
    // No hace falta montar ninguna caché a mano.
    static let rickAndMorty: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = URLCache(
            memoryCapacity: 20 * 1024 * 1024,
            diskCapacity: 100 * 1024 * 1024
        )
        configuration.requestCachePolicy = .useProtocolCachePolicy
        configuration.timeoutIntervalForRequest = 15
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()
}

extension JSONDecoder {
    // La API es toda snake_case (air_date, created), así que con una estrategia me
    // ahorro un CodingKeys en cada DTO
    static var rickAndMorty: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}
