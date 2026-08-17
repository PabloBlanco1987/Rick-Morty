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
    private let isEnabled: Bool

    static let shared = NetworkLogger()

    init(isEnabled: Bool = NetworkLogger.isEnabledByDefault) {
        self.isEnabled = isEnabled
    }

    // Durante los tests se apaga: la suite lanza un montón de peticiones de mentira y el
    // log taparía lo que se está mirando.
    private static var isEnabledByDefault: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
    }

    // MARK: - Puntos de entrada

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
