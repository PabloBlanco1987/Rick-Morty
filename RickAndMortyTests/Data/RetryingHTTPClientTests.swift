import Foundation
import Testing
@testable import RickAndMorty

@Suite("Retrying HTTP client")
struct RetryingHTTPClientTests {
    private func makeSUT(
        policy: RetryPolicy = .default,
        outcomes: [StubHTTPClient.Outcome]
    ) -> (sut: RetryingHTTPClient, stub: StubHTTPClient, recorder: SleepRecorder) {
        let stub = StubHTTPClient(outcomes)
        let recorder = SleepRecorder()
        let sut = RetryingHTTPClient(
            wrapping: stub,
            policy: policy,
            sleep: { await recorder.record($0) }
        )
        return (sut, stub, recorder)
    }

    private var anyEndpoint: Endpoint { RickAndMortyAPI.character(id: 1) }

    @Test("Recovers when a transient failure is followed by a success")
    func retriesUntilSuccess() async throws {
        let (sut, stub, _) = makeSUT(outcomes: [
            .failure(.server(statusCode: 503)),
            .json(JSONFixtures.rick),
        ])

        let dto = try await sut.send(anyEndpoint, as: CharacterDTO.self)

        #expect(dto.id == 1)
        await #expect(stub.callCount == 2)
    }

    @Test("Fails fast on errors a retry cannot fix")
    func doesNotRetryNonRetryableErrors() async {
        let (sut, stub, _) = makeSUT(outcomes: [.failure(.notFound)])

        await #expect(throws: AppError.notFound) {
            _ = try await sut.send(anyEndpoint, as: CharacterDTO.self)
        }
        await #expect(stub.callCount == 1)
    }

    @Test("Being offline is surfaced immediately rather than retried")
    func doesNotRetryOffline() async {
        let (sut, stub, _) = makeSUT(outcomes: [.failure(.offline)])

        await #expect(throws: AppError.offline) {
            _ = try await sut.send(anyEndpoint, as: CharacterDTO.self)
        }
        await #expect(stub.callCount == 1)
    }

    @Test("Gives up after the configured number of attempts, reporting the last error")
    func stopsAtMaxAttempts() async {
        let (sut, stub, _) = makeSUT(outcomes: [.failure(.timeout)])

        await #expect(throws: AppError.timeout) {
            _ = try await sut.send(anyEndpoint, as: CharacterDTO.self)
        }
        await #expect(stub.callCount == 3)
    }

    @Test("Backs off exponentially between attempts")
    func backsOffExponentially() async {
        let (sut, _, recorder) = makeSUT(outcomes: [.failure(.timeout)])

        _ = try? await sut.send(anyEndpoint, as: CharacterDTO.self)

        // Tres intentos son dos esperas: una antes del segundo y otra antes del tercero
        await #expect(recorder.durations == [.milliseconds(300), .milliseconds(600)])
    }

    @Test("Rate limiting is retried, and waited out for longer than a server stumble")
    func backsOffFurtherWhenRateLimited() async {
        // Es lo que separa un scroll rápido que se recupera solo de uno que acaba en
        // una pantalla de error: la API contesta 429 en cuanto le pides varias páginas
        // seguidas, y eso se arregla esperando, no insistiendo a los 300 ms.
        let (sut, stub, recorder) = makeSUT(outcomes: [.failure(.rateLimited)])

        await #expect(throws: AppError.rateLimited) {
            _ = try await sut.send(anyEndpoint, as: CharacterDTO.self)
        }

        await #expect(stub.callCount == 3)
        await #expect(recorder.durations == [.seconds(2), .seconds(4)])
    }

    @Test("A policy of one attempt disables retrying entirely")
    func policyNoneDisablesRetrying() async {
        let (sut, stub, recorder) = makeSUT(policy: .none, outcomes: [.failure(.timeout)])

        await #expect(throws: AppError.timeout) {
            _ = try await sut.send(anyEndpoint, as: CharacterDTO.self)
        }
        await #expect(stub.callCount == 1)
        await #expect(recorder.durations.isEmpty)
    }

    @Test("Being cancelled during the back-off stops retrying and is reported as cancelled")
    func cancellationDuringBackOffStopsRetrying() async {
        // Si el usuario se ha ido de la pantalla mientras se esperaba al segundo intento,
        // gastar los intentos que quedan es gastar peticiones en algo que nadie va a ver.
        // Y lo que sale es .cancelled, no el error que provocó el reintento: la vista lo
        // trata como "no hay nada que contar", no como un fallo.
        let stub = StubHTTPClient([.failure(.timeout)])
        let sut = RetryingHTTPClient(
            wrapping: stub,
            policy: .default,
            // Lo que hace Task.sleep cuando la tarea está cancelada
            sleep: { _ in throw CancellationError() }
        )

        await #expect(throws: AppError.cancelled) {
            _ = try await sut.send(anyEndpoint, as: CharacterDTO.self)
        }
        await #expect(stub.callCount == 1)
    }
}
