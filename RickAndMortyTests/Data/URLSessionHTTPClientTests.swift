import Foundation
import Testing
@testable import RickAndMorty

// Serializada porque StubURLProtocol guarda estado a nivel de proceso: el registro
// de URLProtocol es global, así que dos de estas a la vez se contestarían las
// peticiones la una a la otra.
@Suite("URLSession HTTP client", .serialized)
struct URLSessionHTTPClientTests {
    private let sut = URLSessionHTTPClient(
        base: RickAndMortyAPI.base,
        session: StubURLProtocol.makeSession()
    )

    @Test("Decodes a success payload into the requested type")
    func decodesSuccess() async throws {
        StubURLProtocol.install(.ok(JSONFixtures.rick))

        let dto = try await sut.send(RickAndMortyAPI.character(id: 1), as: CharacterDTO.self)

        #expect(dto.id == 1)
        #expect(dto.name == "Rick Sanchez")
    }

    @Test("Sends the URL the endpoint described")
    func sendsTheBuiltURL() async throws {
        StubURLProtocol.install(.ok(JSONFixtures.charactersPage))

        _ = try await sut.send(
            RickAndMortyAPI.characters(page: 2, filter: CharacterFilter(status: .dead)),
            as: PageDTO<CharacterDTO>.self
        )

        let sent = try #require(StubURLProtocol.lastRequest?.url?.absoluteString)
        #expect(sent.contains("/character"))
        #expect(sent.contains("page=2"))
        #expect(sent.contains("status=dead"))
    }

    @Test("Translates 404 into notFound, keeping the status code out of the domain")
    func mapsNotFound() async {
        StubURLProtocol.install(.status(404, json: JSONFixtures.notFoundError))

        await #expect(throws: AppError.notFound) {
            _ = try await sut.send(RickAndMortyAPI.character(id: 9_999), as: CharacterDTO.self)
        }
    }

    @Test("Carries the status code through for other failures", arguments: [500, 502, 400, 429])
    func mapsServerErrors(statusCode: Int) async {
        StubURLProtocol.install(.status(statusCode))

        await #expect(throws: AppError.server(statusCode: statusCode)) {
            _ = try await sut.send(RickAndMortyAPI.character(id: 1), as: CharacterDTO.self)
        }
    }

    @Test("A payload of the wrong shape is a decoding failure, not a crash")
    func mapsDecodingFailure() async {
        StubURLProtocol.install(.ok(#"{ "unexpected": true }"#))

        await #expect(throws: AppError.decoding) {
            _ = try await sut.send(RickAndMortyAPI.character(id: 1), as: CharacterDTO.self)
        }
    }

    @Test("Connectivity failures surface as offline", arguments: [
        URLError.Code.notConnectedToInternet,
        .networkConnectionLost,
        .dataNotAllowed,
        .cannotFindHost,
    ])
    func mapsOffline(code: URLError.Code) async {
        StubURLProtocol.install(.transport(code))

        await #expect(throws: AppError.offline) {
            _ = try await sut.send(RickAndMortyAPI.character(id: 1), as: CharacterDTO.self)
        }
    }

    @Test("A timeout is distinguishable from being offline")
    func mapsTimeout() async {
        StubURLProtocol.install(.transport(.timedOut))

        await #expect(throws: AppError.timeout) {
            _ = try await sut.send(RickAndMortyAPI.character(id: 1), as: CharacterDTO.self)
        }
    }

    @Test("Cancellation is its own case, never shown as an error to the user")
    func mapsCancellation() async {
        StubURLProtocol.install(.transport(.cancelled))

        await #expect(throws: AppError.cancelled) {
            _ = try await sut.send(RickAndMortyAPI.character(id: 1), as: CharacterDTO.self)
        }
    }
}
