import Foundation
@testable import RickAndMorty

/// An `HTTPClient` that answers from a script of canned outcomes and records what it
/// was asked for.
///
/// An `actor` rather than a lock-guarded class: the recording is mutable state shared
/// across concurrent calls, and the protocol requirement is already `async`, so actor
/// isolation satisfies it without any `@unchecked Sendable`.
actor StubHTTPClient: HTTPClient {
    enum Outcome: Sendable {
        case json(String)
        case failure(AppError)
    }

    private var outcomes: [Outcome]
    private(set) var requestedEndpoints: [Endpoint] = []

    var callCount: Int { requestedEndpoints.count }

    /// Outcomes are consumed in order; the last one repeats forever, so a retry test
    /// can hand over a single failure and still describe every attempt.
    init(_ outcomes: [Outcome]) {
        precondition(!outcomes.isEmpty, "A stub with no outcomes cannot answer anything")
        self.outcomes = outcomes
    }

    init(json: String) { self.init([.json(json)]) }
    init(failure: AppError) { self.init([.failure(failure)]) }

    func send<Response: Decodable & Sendable>(
        _ endpoint: Endpoint,
        as type: Response.Type
    ) async throws(AppError) -> Response {
        requestedEndpoints.append(endpoint)

        let outcome = outcomes.count > 1 ? outcomes.removeFirst() : outcomes[0]

        switch outcome {
        case .failure(let error):
            throw error
        case .json(let json):
            do {
                return try JSONDecoder.rickAndMorty.decode(Response.self, from: Data(json.utf8))
            } catch {
                throw .decoding
            }
        }
    }
}
