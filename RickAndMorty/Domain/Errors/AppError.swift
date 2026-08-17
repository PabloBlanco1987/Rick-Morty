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
    // Nos están pidiendo que bajemos el ritmo. Tiene caso propio y no entra en
    // .server porque no significa lo mismo: el servidor está bien, somos nosotros los
    // que vamos demasiado rápido. Se arregla esperando, no reintentando a lo bruto, y
    // lo que hay que contarle al usuario tampoco se parece.
    case rateLimited
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
        // El caso de libro de "vuelve a intentarlo, pero más tarde". Aguantarlo aquí
        // dentro es lo que evita que un scroll rápido acabe en una pantalla de error:
        // la petición se repite sola con más calma y el usuario no se entera de nada.
        case .rateLimited:
            true
        case .server(let statusCode):
            (500..<600).contains(statusCode)
        case .offline, .notFound, .decoding, .cancelled, .unknown:
            false
        }
    }

    // Cuánto conviene esperar antes de repetir. Un 500 suele ser un tropiezo de
    // milisegundos; un "vas demasiado rápido" no se arregla insistiendo enseguida, que
    // es justo lo que alarga el castigo.
    // Exhaustivo a propósito, igual que isRetryable: un caso nuevo tiene que decidir
    // aquí cuánta paciencia merece, no heredar la de los demás sin que nadie lo mire
    var retryPatience: RetryPatience {
        switch self {
        case .rateLimited: .backOff
        case .offline, .timeout, .notFound, .server, .decoding, .cancelled, .unknown: .brief
        }
    }

    enum RetryPatience: Sendable {
        case brief
        case backOff
    }
}
