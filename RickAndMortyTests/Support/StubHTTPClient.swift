import Foundation
@testable import RickAndMorty

/// An `HTTPClient` that answers from a list of prepared responses and records what it
/// was asked. An actor rather than a class with a lock: what it records is state shared
/// across concurrent calls, and since the protocol is already async, actor isolation
/// covers it with no `@unchecked Sendable`.
actor StubHTTPClient: HTTPClient {
    enum Outcome: Sendable {
        case json(String)
        case failure(AppError)
    }

    private var outcomes: [Outcome]
    private(set) var requestedEndpoints: [Endpoint] = []

    var callCount: Int { requestedEndpoints.count }

    // Responses are consumed in order and the last one repeats forever, so a retry
    // test can pass a single failure and cover every attempt.
    init(_ outcomes: [Outcome]) {
        precondition(!outcomes.isEmpty, "A stub with no outcomes cannot answer anything")
        self.outcomes = outcomes
    }

    init(json: String) { self.init([.json(json)]) }

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
