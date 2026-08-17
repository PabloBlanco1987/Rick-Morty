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
// Los textos viven en un String Catalog (Localizable.xcstrings), con claves
// "appError.<caso>.title" / "appError.<caso>.message". El sitio ya estaba preparado
// para esto: entrar como localizaciones no ha cambiado la forma de esta extensión ni ha
// tocado una sola vista.
extension AppError {
    var title: String {
        switch self {
        case .offline: String(localized: .appErrorOfflineTitle)
        case .timeout: String(localized: .appErrorTimeoutTitle)
        case .notFound: String(localized: .appErrorNotFoundTitle)
        case .rateLimited: String(localized: .appErrorRateLimitedTitle)
        case .server: String(localized: .appErrorServerTitle)
        case .decoding: String(localized: .appErrorDecodingTitle)
        case .cancelled, .unknown: String(localized: .appErrorUnknownTitle)
        }
    }

    var message: String {
        switch self {
        case .offline:
            String(localized: .appErrorOfflineMessage)
        case .timeout:
            String(localized: .appErrorTimeoutMessage)
        case .notFound:
            String(localized: .appErrorNotFoundMessage)
        case .rateLimited:
            String(localized: .appErrorRateLimitedMessage)
        case .server:
            String(localized: .appErrorServerMessage)
        case .decoding:
            String(localized: .appErrorDecodingMessage)
        case .cancelled, .unknown:
            String(localized: .appErrorUnknownMessage)
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
