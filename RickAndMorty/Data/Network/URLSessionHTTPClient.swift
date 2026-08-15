import Foundation

// El único sitio de la app que habla con la red.
// Todo lo que puede fallar (transporte, código de estado, payload roto) se traduce a
// AppError antes de salir de aquí, así que URLError y DecodingError no se escapan
// nunca de la capa de datos.
struct URLSessionHTTPClient: HTTPClient {
    private let base: URLComponents
    private let session: URLSession

    init(base: URLComponents = RickAndMortyAPI.base, session: URLSession = .rickAndMorty) {
        self.base = base
        self.session = session
    }

    func send<Response: Decodable & Sendable>(
        _ endpoint: Endpoint,
        as type: Response.Type
    ) async throws(AppError) -> Response {
        guard let request = endpoint.urlRequest(base: base) else {
            throw .unknown
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw AppError(error)
        } catch is CancellationError {
            throw .cancelled
        } catch {
            throw .unknown
        }

        guard let http = response as? HTTPURLResponse else { throw .unknown }

        if let error = AppError(statusCode: http.statusCode) { throw error }

        do {
            // JSONDecoder no es Sendable, así que lo creo en cada llamada en vez de
            // guardarlo. Crearlo cuesta microsegundos frente a una petición de
            // decenas de milisegundos: no compensa un @unchecked Sendable.
            return try JSONDecoder.rickAndMorty.decode(Response.self, from: data)
        } catch {
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
