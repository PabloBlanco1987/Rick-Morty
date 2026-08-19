import Foundation
import Testing
@testable import RickAndMorty

/// Shared setup for the three listing suites — paging, search/filters, refresh — to
/// build and drive the view model. Written once so all three stay in sync; three
/// separate copies is the easiest way for only one to still know how a month from now.
@MainActor
extension CharacterListViewModel {
    // Records the between-page throttle and the search debounce instead of sleeping:
    // keeps the suite in milliseconds and lets them be asserted on.
    static func forTesting(
        _ repository: StubCharacterRepository,
        recordingWaitsInto recorder: SleepRecorder? = nil
    ) -> CharacterListViewModel {
        CharacterListViewModel(
            fetchCharacters: FetchCharactersUseCase(repository: repository),
            sleep: { await recorder?.record($0) }
        )
    }

    // The view model paired with a repository stubbed per page — what's needed to
    // test pagination and to inspect state after a failure.
    static func forTesting(pages: [Int: Result<Page<Character>, AppError>]) -> (
        CharacterListViewModel, StubCharacterRepository
    ) {
        let repository = StubCharacterRepository(charactersByPage: pages)
        return (forTesting(repository), repository)
    }

    // Simulates the last loaded cell appearing — what the grid does at the bottom —
    // and waits for whatever that triggers to finish.
    func scrollToTheEnd() async throws {
        let last = try #require(state.value?.last)
        loadNextPageIfNeeded(after: last)
        await pagingTask?.value
    }
}
