import Foundation

// El único error que cruza una frontera entre capas.
// URLError, DecodingError y los códigos HTTP se traducen a estos casos dentro de la
// capa de datos, así ni el dominio ni los view models saben qué es un status code.
// Presentación convierte cada caso en su texto.
enum AppError: Error, Equatable, Sendable {
    // No hay conexión
    case offline
    // La petición se pasó del timeout
    case timeout
    // El recurso no existe de verdad
    case notFound
    // El servidor contesta, pero no con un 2xx
    case server(statusCode: Int)
    // Llega el payload pero no tiene la forma esperada
    case decoding
    // Cancelado, normalmente una búsqueda que ya no vale. No se enseña nunca
    case cancelled
    case unknown

    // Si reintentar solo tiene sentido o no.
    // La falta de conexión queda fuera aposta: reintentar 300 ms después de perder
    // cobertura casi nunca funciona, y prefiero enseñar el botón de reintentar ya
    // que tener al usuario un segundo mirando un spinner.
    var isRetryable: Bool {
        switch self {
        case .timeout:
            true
        case .server(let statusCode):
            (500..<600).contains(statusCode)
        case .offline, .notFound, .decoding, .cancelled, .unknown:
            false
        }
    }
}
