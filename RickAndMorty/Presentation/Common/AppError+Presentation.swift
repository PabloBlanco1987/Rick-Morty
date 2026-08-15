import Foundation

// Cómo se cuenta cada fallo.
// Vive en presentación porque el dominio dice qué ha pasado y la pantalla decide cómo
// se dice: el mismo AppError.offline se lee distinto en una pantalla completa que en
// un pie de lista.
//
// Todos los textos siguen la misma regla: primero qué ha pasado, después qué puede
// hacer el usuario. "Error 500" no es ninguna de las dos cosas, y un código de estado
// no le dice nada a nadie que no esté leyendo los logs.
//
// TODO: [Fase 05] Los textos están en inglés y en el código. Se quedan así porque
// localizar de verdad es sacar el catálogo de String Catalogs, decidir la pluralización
// y revisar que los textos largos no rompan el layout en alemán, y eso es una fase
// entera. Entrarían como LocalizedStringResource sobre un Localizable.xcstrings, sin
// tocar la forma de esta extensión.
extension AppError {
    var title: String {
        switch self {
        case .offline: "No connection"
        case .timeout: "This is taking too long"
        case .notFound: "Nothing here"
        case .rateLimited: "Easy there"
        case .server: "The server is having a bad day"
        case .decoding: "Something came back wrong"
        case .cancelled, .unknown: "Something went wrong"
        }
    }

    var message: String {
        switch self {
        case .offline:
            "Check your Wi-Fi or mobile data and try again."
        case .timeout:
            "The connection is slow right now. Try again in a moment."
        case .notFound:
            "We couldn't find what you were looking for."
        case .rateLimited:
            "We're asking for characters faster than the server will hand them over. Give it a second."
        case .server:
            "It's not you. Give it a moment and try again."
        case .decoding:
            "We couldn't read the answer. Try again, and if it keeps happening it's on us."
        case .cancelled, .unknown:
            "Try again."
        }
    }

    var systemImage: String {
        switch self {
        case .offline: "wifi.slash"
        case .timeout: "clock.badge.exclamationmark"
        case .notFound: "magnifyingglass"
        case .rateLimited: "hourglass"
        case .server: "exclamationmark.icloud"
        case .decoding, .cancelled, .unknown: "exclamationmark.triangle"
        }
    }
}
