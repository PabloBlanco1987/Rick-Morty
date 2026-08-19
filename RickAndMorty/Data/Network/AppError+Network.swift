import Foundation

/// Translating "whatever URLSession returns" into AppError, in one place. Lives here
/// and not inside URLSessionHTTPClient because ImageCache downloads on its own — it
/// doesn't go through HTTPClient, which decodes JSON — and needs this exact same table.
/// Two identical switches in two files is the easiest way for only one of them to know
/// what a 429 is a month from now.
extension AppError {
    init(_ error: URLError) {
        self = switch error.code {
        // cannotFindHost and dnsLookupFailed are the same thing seen from two angles:
        // no network means nobody to resolve the name. cannotConnectToHost is included
        // too, even though it could be the server down with the network fine — the
        // instruction to the user is the same either way (check the connection, try
        // again), and retrying against a host that isn't answering fixes nothing.
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

    // nil when the code is a 2xx — i.e. when there's nothing to translate. Returning
    // an optional instead of throwing leaves the decision of what to do to the caller,
    // who knows whether it's inside a guard or a do.
    init?(statusCode: Int) {
        switch statusCode {
        case 200..<300:
            return nil
        case 404:
            self = .notFound
        // The API sits behind Cloudflare and answers 429 with "Error 1015: you are
        // being rate limited" as soon as it's asked for several pages in a row —
        // exactly what a fast scroll produces.
        case 429:
            self = .rateLimited
        default:
            self = .server(statusCode: statusCode)
        }
    }
}
