import Foundation
import Testing
@testable import RickAndMorty

// Apunta la secuencia de esperas en vez de dormir de verdad, así la suite entera
// tarda milisegundos y no segundos
private actor SleepRecorder {
    private(set) var durations: [Duration] = []
    func record(_ duration: Duration) { durations.append(duration) }
}

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

    @Test("A policy of one attempt disables retrying entirely")
    func policyNoneDisablesRetrying() async {
        let (sut, stub, recorder) = makeSUT(policy: .none, outcomes: [.failure(.timeout)])

        await #expect(throws: AppError.timeout) {
            _ = try await sut.send(anyEndpoint, as: CharacterDTO.self)
        }
        await #expect(stub.callCount == 1)
        await #expect(recorder.durations.isEmpty)
    }
}
