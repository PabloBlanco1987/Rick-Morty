import Foundation

// La traducción de "lo que devuelve URLSession" a AppError, en un solo sitio.
// Está aquí y no dentro de URLSessionHTTPClient porque ImageCache descarga por su
// cuenta —no pasa por HTTPClient, que decodifica JSON— y necesita exactamente la
// misma tabla. Dos switch idénticos en dos ficheros es la forma más fácil de que
// dentro de un mes solo uno de los dos sepa qué es un 429.
extension AppError {
    init(_ error: URLError) {
        self = switch error.code {
        // cannotFindHost y dnsLookupFailed son la misma cosa vista desde dos sitios: sin
        // red no hay quien resuelva el nombre. cannotConnectToHost entra también aunque
        // pueda ser el servidor caído con la red bien: para el usuario la instrucción es
        // la misma —comprobar la conexión y volver a intentarlo—, y reintentar solo
        // contra un host que no contesta tampoco arregla nada.
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed,
             .internationalRoamingOff, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
            .offline
        case .timedOut:
            .timeout
        case .cancelled:
            .cancelled
        default:
            .unknown
        }
    }

    // nil cuando el código es un 2xx, o sea cuando no hay nada que traducir.
    // Devolver un opcional y no lanzar deja la decisión de qué hacer en quien llama,
    // que es el que sabe si está en un guard o dentro de un do.
    init?(statusCode: Int) {
        switch statusCode {
        case 200..<300:
            return nil
        case 404:
            self = .notFound
        // La API va detrás de Cloudflare y contesta 429 con un "Error 1015: you are
        // being rate limited" en cuanto le pides varias páginas seguidas, que es
        // exactamente lo que produce un scroll rápido.
        case 429:
            self = .rateLimited
        default:
            self = .server(statusCode: statusCode)
        }
    }
}
