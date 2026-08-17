import Foundation
import OSLog

// La traza de red para depurar: por consola sale qué se pide y con qué código contesta
// el servidor, con lo que ha tardado. Una línea por petición y otra por respuesta, sin
// volcar el cuerpo: para seguir qué está llamando la app eso sobra, y una sola página de
// personajes son ~19 KB de JSON que dejarían la consola ilegible.
//
// Va aquí y no en un decorador como RetryingHTTPClient aposta: un decorador solo ve el
// Endpoint que entra y el modelo ya decodificado que sale, así que no puede enseñar el
// código de estado. Este es el único sitio de la app con la respuesta cruda delante.
//
// En release no queda nada: los cuerpos se compilan solo en DEBUG y las llamadas desde
// URLSessionHTTPClient se quedan vacías.
struct NetworkLogger: Sendable {
    // Una sola traza para toda la app: quien la usa la nombra directamente, no se
    // inyecta. Es la excepción a la regla de inyectar y está aquí a propósito: nadie
    // necesita otra —los tests la apagan por entorno— y un parámetro que nadie pasa es
    // un seam de mentira.
    static let shared = NetworkLogger()

    // Durante los tests se apaga: la suite lanza un montón de peticiones de mentira y el
    // log taparía lo que se está mirando.
    private let isEnabled = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil

    private init() {}

    // MARK: - Puntos de entrada

    // Las URLs salen con privacy: .public a sabiendas, y con ellas lo que el usuario
    // teclea en la búsqueda (?name=...). Es una traza de depuración que solo existe en
    // DEBUG, contra una API pública, y redactar la query sería dejar la consola sin lo
    // único que hace falta ver: qué se está pidiendo. En un producto con datos
    // personales de verdad la query iría con la privacidad por defecto.
    func logRequest(_ request: URLRequest) {
        #if DEBUG
        guard isEnabled else { return }
        Self.log.debug("📤 Request \(summary(of: request), privacy: .public)")
        #endif
    }

    func logResponse(_ response: HTTPURLResponse, for request: URLRequest, duration: Duration) {
        #if DEBUG
        guard isEnabled else { return }
        let line = "📥 Response \(response.statusCode) \(summary(of: request)) · \(formatted(duration))"
        // Un 2xx es ruido de fondo y un 404 o un 500 es lo que se está buscando, así que
        // salen por niveles distintos y el filtro de la consola los separa.
        if (200..<300).contains(response.statusCode) {
            Self.log.debug("\(line, privacy: .public)")
        } else {
            Self.log.error("\(line, privacy: .public)")
        }
        #endif
    }

    // Vale igual para un fallo de transporte y para un payload que no decodifica: en los
    // dos casos lo útil es el error de verdad, que a partir de aquí se traduce a AppError
    // y se pierde. Un DecodingError trae la ruta exacta de la clave que no cuadra.
    func logFailure(_ error: some Error, for request: URLRequest, duration: Duration) {
        #if DEBUG
        guard isEnabled else { return }
        let line = "❌ Response \(summary(of: request)) · \(formatted(duration)) · \(String(describing: error))"
        Self.log.error("\(line, privacy: .public)")
        #endif
    }

    // Lo que decide el limitador de ritmo: cuándo se frena y a qué ritmo se vuelve. Sale
    // como aviso y no como depuración porque es lo que hay que mirar cuando la rejilla
    // se queda gris: dice si el servidor nos ha parado y cuánto.
    // @autoclosure para que el texto —con sus duraciones y ritmos interpolados— solo se
    // construya cuando de verdad se va a escribir: en release el cuerpo se compila vacío
    // y no tendría sentido pagar el formateo para tirarlo.
    func logThrottle(_ message: @autoclosure () -> String) {
        #if DEBUG
        guard isEnabled else { return }
        let text = message()
        Self.log.notice("\(text, privacy: .public)")
        #endif
    }

    // MARK: - Formato

    #if DEBUG
    private static let log = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "RickAndMorty",
        category: "Network"
    )

    private func summary(of request: URLRequest) -> String {
        "\(request.httpMethod ?? "GET") \(request.url?.absoluteString ?? "-")"
    }

    private func formatted(_ duration: Duration) -> String {
        let milliseconds = Double(duration.components.seconds) * 1_000
            + Double(duration.components.attoseconds) * 1e-15
        return String(format: "%.0f ms", milliseconds)
    }
    #endif
}
