import Foundation
import Testing
@testable import RickAndMorty

/// What's tested here, more than loading itself, is the screen's rule: what was
/// already known at navigation time shows up immediately, and an episodes failure
/// doesn't take the character down with it.
@MainActor
@Suite("Character detail view model")
struct CharacterDetailViewModelTests {
    private func makeSUT(
        _ repository: StubCharacterRepository,
        known: Character? = nil,
        id: Int = 1
    ) -> CharacterDetailViewModel {
        CharacterDetailViewModel(
            characterID: id,
            known: known,
            fetchCharacterDetail: FetchCharacterDetailUseCase(repository: repository)
        )
    }

    private let episodes = [
        Episode(id: 1, name: "Pilot", code: "S01E01", airDate: nil),
        Episode(id: 2, name: "Lawnmower Dog", code: "S01E02", airDate: nil),
    ]

    // MARK: - Loading

    @Test("Starts idle, with nothing loaded")
    func startsIdle() {
        let sut = makeSUT(StubCharacterRepository())

        #expect(sut.state == .idle)
        #expect(sut.episodes.isEmpty)
    }

    @Test("The character that came from the list is on screen before anything is requested")
    func showsTheKnownCharacterUpFront() async {
        // This is the whole point of this screen: tapping a cell already reveals the
        // name, so making the user wait on the server to show it would be a made-up
        // delay.
        let repository = StubCharacterRepository()
        let sut = makeSUT(repository, known: .stub(name: "Rick Sanchez"))

        #expect(sut.character?.name == "Rick Sanchez")
        #expect(sut.hasContentOnScreen)
        #expect(await repository.requestedCharacterIDs.isEmpty)
    }

    @Test("Loading brings the character together with its episodes")
    func loadsCharacterAndEpisodes() async {
        let repository = StubCharacterRepository(
            character: .success(.stub(episodeIDs: [1, 2])),
            episodes: .success(episodes)
        )
        let sut = makeSUT(repository, id: 42)

        await sut.onAppear()

        #expect(sut.character?.name == "Rick Sanchez")
        #expect(sut.episodes.map(\.code) == ["S01E01", "S01E02"])
        #expect(await repository.requestedCharacterIDs == [42])
    }

    @Test("What the server returns wins over what the list had")
    func theLoadedCharacterReplacesTheKnownOne() async {
        // The list may have loaded ten minutes ago: if the character has since changed
        // location, what just arrived wins.
        let repository = StubCharacterRepository(character: .success(.stub(name: "Rick Sanchez")))
        let sut = makeSUT(repository, known: .stub(name: "Stale name"))

        await sut.onAppear()

        #expect(sut.character?.name == "Rick Sanchez")
    }

    @Test("Appearing again does not reload what is already on screen")
    func appearingAgainDoesNotReload() async {
        let repository = StubCharacterRepository()
        let sut = makeSUT(repository)

        await sut.onAppear()
        await sut.onAppear()

        #expect(await repository.requestedCharacterIDs == [1])
    }

    @Test("A character with no episodes is a loaded detail with an empty list, not a failure")
    func noEpisodesIsLoadedNotFailed() async {
        // That nothing gets requested for them is the use case's job; what matters
        // here is that the screen treats it as a result — "in no episodes" — not as a
        // section error
        let character = Character.stub(episodeIDs: [])
        let sut = makeSUT(StubCharacterRepository(character: .success(character)))

        await sut.onAppear()

        #expect(sut.state == .loaded(CharacterDetail(character: character, episodes: [])))
        #expect(sut.episodes.isEmpty)
    }

    @Test("Being cancelled is not failing: nothing is written for it")
    func aCancelledLoadIsNotAFailure() async {
        // If the user navigated back while loading, the request is cancelled and there's
        // nothing to report: no error in the episodes section, none on the screen
        let sut = makeSUT(StubCharacterRepository(character: .failure(.cancelled)), known: .stub())

        await sut.onAppear()

        #expect(sut.state == .loading)
        #expect(sut.hasContentOnScreen)
    }

    // MARK: - Failures

    @Test("A failure keeps the character that was already on screen")
    func failureKeepsTheKnownCharacter() async {
        // Only the episodes failed. Replacing a character already on screen with an
        // error page would trade information for a message.
        let repository = StubCharacterRepository(episodes: .failure(.offline))
        let sut = makeSUT(repository, known: .stub(name: "Rick Sanchez"))

        await sut.onAppear()

        #expect(sut.state == .failed(.offline))
        #expect(sut.character?.name == "Rick Sanchez")
        #expect(sut.hasContentOnScreen)
    }

    @Test("A failure with nothing on screen takes over the whole view")
    func failureWithoutContentOwnsTheScreen() async {
        // Nothing to preserve here: entered without a character — a deep link — and
        // the request failed, so the error is the whole screen.
        let repository = StubCharacterRepository(character: .failure(.notFound))
        let sut = makeSUT(repository)

        await sut.onAppear()

        #expect(sut.state == .failed(.notFound))
        #expect(!sut.hasContentOnScreen)
    }

    @Test("Retrying asks for the detail again")
    func retryingAsksAgain() async {
        let repository = StubCharacterRepository(character: .failure(.timeout))
        let sut = makeSUT(repository, id: 7)

        await sut.onAppear()
        await sut.retry()

        #expect(await repository.requestedCharacterIDs == [7, 7])
    }

    @Test("A retry that succeeds replaces the error with the detail")
    func retryRecovers() async {
        let repository = StubCharacterRepository(
            character: .success(.stub(episodeIDs: [1, 2])),
            episodes: .failure(.server(statusCode: 503))
        )
        let sut = makeSUT(repository)
        await sut.onAppear()
        #expect(sut.state == .failed(.server(statusCode: 503)))

        await repository.setEpisodes(.success(episodes))
        await sut.retry()

        #expect(sut.episodes.count == 2)
    }
}
