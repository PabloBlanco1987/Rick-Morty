import Foundation

/// How each failure gets told. Lives in Presentation because the domain says what
/// happened and the screen decides how to say it — the same AppError.offline reads
/// differently full-screen than in a list footer. Every string follows the same rule:
/// what happened, then what the user can do — "Error 500" is neither, and a status
/// code means nothing to anyone not reading logs. Text lives in a String Catalog
/// (Localizable.xcstrings), keyed "appError.<case>.title" / "appError.<case>.message".
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
