import Foundation

// El sitio por el que sale a la red todo el JSON de la app. El otro es la descarga de
// imágenes de ImageCache, que trae bytes y no modelos; los dos comparten la traducción
// de fallos de AppError+Network, la traza y el limitador de ritmo.
// Todo lo que puede fallar (transporte, código de estado, payload roto) se traduce a
// AppError antes de salir de aquí, así que URLError y DecodingError no se escapan
// nunca de la capa de datos.
struct URLSessionHTTPClient: HTTPClient {
    private let base: URLComponents
    private let session: URLSession
    private let limiter: RateLimiter
    private let logger = NetworkLogger.shared

    init(
        base: URLComponents = RickAndMortyAPI.base,
        session: URLSession = .rickAndMorty,
        // El mismo que usa la caché de imágenes: el cupo del servidor es uno para JSON
        // e imágenes, así que el freno tiene que ser el mismo objeto
        limiter: RateLimiter = .shared
    ) {
        self.base = base
        self.session = session
        self.limiter = limiter
    }

    func send<Response: Decodable & Sendable>(
        _ endpoint: Endpoint,
        as type: Response.Type
    ) async throws(AppError) -> Response {
        guard let request = endpoint.urlRequest(base: base) else {
            throw .unknown
        }

        // Ficha, traza, transporte y código de estado van en URLSession.perform, que es
        // lo mismo que usa la descarga de imágenes. Aquí solo queda lo propio del JSON:
        // convertir los bytes en un modelo.
        let exchange = try await session.perform(request, through: limiter)

        do {
            return try JSONDecoder.rickAndMorty.decode(Response.self, from: exchange.data)
        } catch {
            // El DecodingError trae la ruta exacta de la clave que no cuadra, y al salir
            // de aquí como .decoding se pierde. Es la única traza que lo cuenta.
            logger.logFailure(error, for: request, duration: exchange.duration)
            throw .decoding
        }
    }
}

extension URLSession {
    // La sesión con la que va la app.
    // Toda la caché de respuestas es este URLCache privado: la API manda ETag y un
    // Cache-Control de noventa días, así que con .useProtocolCachePolicy una página ya
    // vista sale directamente de disco sin tocar la red —volver del detalle o repetir una
    // búsqueda no cuestan una petición— y solo se revalida con una condicional (un 304
    // sin cuerpo) cuando el endpoint lo pide a propósito, que es lo que hace el pull to
    // refresh a través de Freshness. No hace falta montar ninguna caché a mano.
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
    // ahorro un CodingKeys en cada DTO.
    // Una sola instancia compartida: JSONDecoder es Sendable desde iOS 16, así que
    // configurarlo una vez y reutilizarlo no necesita ningún @unchecked, y es lo que
    // se espera de un decodificador que siempre se configura igual.
    static let rickAndMorty: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()
}
