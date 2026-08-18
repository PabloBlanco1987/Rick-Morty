import Foundation
@testable import RickAndMorty

// HTTPClient que contesta desde una lista de respuestas preparadas y apunta lo que
// le han pedido.
// Es un actor y no una clase con lock: lo que apunta es estado mutable compartido
// entre llamadas concurrentes, y como el protocolo ya es async, el aislamiento del
// actor lo cumple sin ningún @unchecked Sendable.
actor StubHTTPClient: HTTPClient {
    enum Outcome: Sendable {
        case json(String)
        case failure(AppError)
    }

    private var outcomes: [Outcome]
    private(set) var requestedEndpoints: [Endpoint] = []

    var callCount: Int { requestedEndpoints.count }

    // Las respuestas se consumen en orden y la última se repite siempre, así un test
    // de reintentos puede pasar un solo fallo y cubrir todos los intentos
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
