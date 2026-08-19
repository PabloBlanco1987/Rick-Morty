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

        // Three attempts mean two waits: one before the second, one before the third
        await #expect(recorder.durations == [.milliseconds(300), .milliseconds(600)])
    }

    @Test("Rate limiting is retried, and waited out for longer than a server stumble")
    func backsOffFurtherWhenRateLimited() async {
        // This separates a fast scroll that recovers on its own from one that ends in
        // an error screen: the API answers 429 as soon as you request several pages in
        // a row, and that's fixed by waiting, not by retrying every 300ms.
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
        // If the user has left the screen while waiting for the second attempt,
        // spending the remaining attempts wastes requests on something nobody will see.
        // What comes out is .cancelled, not the error that triggered the retry: the
        // view treats it as "nothing to report", not a failure.
        let stub = StubHTTPClient([.failure(.timeout)])
        let sut = RetryingHTTPClient(
            wrapping: stub,
            policy: .default,
            // What Task.sleep does when the task is cancelled
            sleep: { _ in throw CancellationError() }
        )

        await #expect(throws: AppError.cancelled) {
            _ = try await sut.send(anyEndpoint, as: CharacterDTO.self)
        }
        await #expect(stub.callCount == 1)
    }
}
