import Foundation
import Testing
@testable import RickAndMorty

/// `@MainActor` because the view model is: tests call its methods from the same
/// isolation as the view, so what's tested is the real order of things.
@MainActor
@Suite("Character list view model")
struct CharacterListViewModelTests {
    // MARK: - Initial load

    @Test("Starts idle, with nothing loading and no page error")
    func startsIdle() {
        let sut = CharacterListViewModel.forTesting(StubCharacterRepository())

        #expect(sut.state == .idle)
        #expect(!sut.isLoadingNextPage)
        #expect(sut.nextPageError == nil)
    }

    @Test("The first page that arrives becomes the loaded state")
    func loadsFirstPage() async {
        let (sut, repository) = CharacterListViewModel.forTesting(pages: [
            1: .success(.stub(page: 1, totalPages: 3, ids: 1...5)),
        ])

        await sut.onAppear()

        #expect(sut.state.value?.map(\.id) == [1, 2, 3, 4, 5])
        #expect(await repository.requestedPages == [1])
    }

    @Test("A first page with no characters is empty, which is not the same as failed")
    func emptyFirstPage() async {
        let (sut, _) = CharacterListViewModel.forTesting(pages: [
            1: .success(.empty()),
        ])

        await sut.onAppear()

        #expect(sut.state == .empty)
    }

    @Test("Appearing again does not reload what is already on screen")
    func appearingAgainDoesNotReload() async {
        // .task fires again every time the view appears. If that reloaded, coming back
        // from the detail screen would cost the whole list and the scroll position.
        let (sut, repository) = CharacterListViewModel.forTesting(pages: [
            1: .success(.stub(page: 1, totalPages: 3, ids: 1...5)),
        ])

        await sut.onAppear()
        await sut.onAppear()

        #expect(await repository.requestedPages == [1])
    }

    // MARK: - Pagination

    @Test("The next page is appended to what is already on screen")
    func appendsNextPage() async throws {
        let (sut, repository) = CharacterListViewModel.forTesting(pages: [
            1: .success(.stub(page: 1, totalPages: 3, ids: 1...5)),
            2: .success(.stub(page: 2, totalPages: 3, ids: 6...10)),
        ])
        await sut.onAppear()

        try await sut.scrollToTheEnd()

        #expect(sut.state.value?.map(\.id) == [1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
        #expect(await repository.requestedPages == [1, 2])
        #expect(!sut.isLoadingNextPage)
    }

    @Test("Two cells appearing at once only ask for the next page once")
    func guardsAgainstDuplicateNextPageLoads() async throws {
        let (sut, repository) = CharacterListViewModel.forTesting(pages: [
            1: .success(.stub(page: 1, totalPages: 3, ids: 1...5)),
            2: .success(.stub(page: 2, totalPages: 3, ids: 6...10)),
        ])
        await sut.onAppear()
        let trigger = try #require(sut.state.value?.last)

        // Two calls back to back with no await in between: exactly what happens when
        // two grid cells appear in the same layout cycle.
        sut.loadNextPageIfNeeded(after: trigger)
        sut.loadNextPageIfNeeded(after: trigger)
        await sut.pagingTask?.value

        #expect(await repository.requestedPages == [1, 2])
        #expect(sut.state.value?.count == 10)
    }

    @Test("A page asked for right after the previous one has to wait its turn")
    func brakesBetweenPagesAskedForBackToBack() async throws {
        // Without the brake, a fast gesture chains several pages in under a second:
        // one arrives, its cells appear while the finger is still moving, and that
        // requests the next one. That's a hundred characters nobody looks at, and a
        // burst that earns a 429 from the API — one that also crowds out the load
        // that actually mattered.
        let waits = SleepRecorder()
        let repository = StubCharacterRepository(charactersByPage: [
            1: .success(.stub(page: 1, totalPages: 3, ids: 1...5)),
            2: .success(.stub(page: 2, totalPages: 3, ids: 6...10)),
        ])
        let sut = CharacterListViewModel.forTesting(repository, recordingWaitsInto: waits)
        await sut.onAppear()

        try await sut.scrollToTheEnd()

        // It waited, and less than the full brake duration: what's discounted is the
        // time already spent fetching the previous page
        let durations = await waits.durations
        #expect(durations.count == 1)
        #expect(durations.allSatisfy { $0 > .zero && $0 <= .milliseconds(400) })
        #expect(sut.state.value?.count == 10)
    }

    @Test("A page asked for long after the previous one goes straight through")
    func doesNotBrakeWhenTheUserTakesTheirTime() async throws {
        // The brake is against bursts, not against the user: scrolling down while
        // reading shouldn't have to wait at all.
        let waits = SleepRecorder()
        let repository = StubCharacterRepository(charactersByPage: [
            1: .success(.stub(page: 1, totalPages: 3, ids: 1...5)),
            2: .success(.stub(page: 2, totalPages: 3, ids: 6...10)),
        ])
        let sut = CharacterListViewModel.forTesting(repository, recordingWaitsInto: waits)
        await sut.onAppear()
        try await Task.sleep(for: .milliseconds(450))

        try await sut.scrollToTheEnd()

        #expect(await waits.durations.isEmpty)
    }

    @Test("A cell that is not near the end does not ask for anything")
    func onlyTheLastCellsTrigger() async throws {
        let (sut, repository) = CharacterListViewModel.forTesting(pages: [
            1: .success(.stub(page: 1, totalPages: 3, ids: 1...20)),
        ])
        await sut.onAppear()
        let first = try #require(sut.state.value?.first)

        sut.loadNextPageIfNeeded(after: first)
        await sut.pagingTask?.value

        #expect(await repository.requestedPages == [1])
    }

    @Test("Nothing is asked for past the last page")
    func stopsAtTheLastPage() async throws {
        let (sut, repository) = CharacterListViewModel.forTesting(pages: [
            1: .success(.stub(page: 1, totalPages: 1, ids: 1...5)),
        ])
        await sut.onAppear()

        try await sut.scrollToTheEnd()

        #expect(await repository.requestedPages == [1])
        #expect(!sut.isLoadingNextPage)
    }

    @Test("A character that comes back in two pages is only shown once")
    func doesNotShowTheSameCharacterTwice() async throws {
        // The API paginates over a stable list, but if two pages brought back the same
        // character, ForEach would end up with two equal ids and SwiftUI would lose
        // track of which cell is which. And only the new images get warmed into cache.
        let (sut, _) = CharacterListViewModel.forTesting(pages: [
            1: .success(.stub(page: 1, totalPages: 2, ids: 1...5)),
            2: .success(.stub(page: 2, totalPages: 2, ids: 4...8)),
        ])
        await sut.onAppear()

        try await sut.scrollToTheEnd()

        #expect(sut.state.value?.map(\.id) == [1, 2, 3, 4, 5, 6, 7, 8])
        #expect(sut.latestPageImageURLs.map(\.absoluteString) == (6...8).map(avatar))
    }

    // MARK: - Images to warm

    @Test("The images to warm are the ones of the page that just arrived, not everything loaded")
    func publishesTheImagesOfTheLatestPage() async throws {
        // What's already been seen is already on disk; what needs warming is what's
        // coming. Publishing the whole list would make the view re-scan eight hundred
        // URLs for every new page.
        let (sut, _) = CharacterListViewModel.forTesting(pages: [
            1: .success(.stub(page: 1, totalPages: 3, ids: 1...5)),
            2: .success(.stub(page: 2, totalPages: 3, ids: 6...10)),
        ])

        await sut.onAppear()
        #expect(sut.latestPageImageURLs.map(\.absoluteString) == (1...5).map(avatar))

        try await sut.scrollToTheEnd()
        #expect(sut.latestPageImageURLs.map(\.absoluteString) == (6...10).map(avatar))
    }

    @Test("A character without an image URL is left out of what is warmed")
    func leavesOutCharactersWithoutImage() async {
        let withoutImage = Character(
            id: 1,
            name: "No face",
            status: .unknown,
            species: "Human",
            type: nil,
            gender: .unknown,
            origin: "?",
            location: "?",
            imageURL: nil,
            episodeIDs: []
        )
        let page = Page(items: [withoutImage, .stub(id: 2)], currentPage: 1, totalPages: 1)
        let (sut, _) = CharacterListViewModel.forTesting(pages: [
            1: .success(page),
        ])

        await sut.onAppear()

        #expect(sut.latestPageImageURLs.map(\.absoluteString) == [avatar(2)])
    }

    private func avatar(_ id: Int) -> String {
        "https://rickandmortyapi.com/api/character/avatar/\(id).jpeg"
    }

    // MARK: - Failures

    @Test("A first page that fails takes over the screen")
    func firstPageFailureReplacesTheScreen() async {
        let (sut, _) = CharacterListViewModel.forTesting(pages: [
            1: .failure(.server(statusCode: 500)),
        ])

        await sut.onAppear()

        #expect(sut.state == .failed(.server(statusCode: 500)))
        #expect(sut.nextPageError == nil)
    }

    @Test("A next page that fails keeps the pages already on screen")
    func nextPageFailureKeepsWhatIsLoaded() async throws {
        // This is the difference between a screen failure and a page failure: if the
        // next page fails, the five the user is looking at are still valid.
        let (sut, _) = CharacterListViewModel.forTesting(pages: [
            1: .success(.stub(page: 1, totalPages: 3, ids: 1...5)),
            2: .failure(.offline),
        ])
        await sut.onAppear()

        try await sut.scrollToTheEnd()

        #expect(sut.state.value?.map(\.id) == [1, 2, 3, 4, 5])
        #expect(sut.nextPageError == .offline)
        #expect(!sut.isLoadingNextPage)
    }

    @Test("A failed next page is not retried on its own while the user keeps scrolling")
    func aFailedNextPageDoesNotRetryItself() async throws {
        // The trailing cells keep appearing after the failure. Without the guard, each
        // appearance would fire another request at a server that already said no.
        let (sut, repository) = CharacterListViewModel.forTesting(pages: [
            1: .success(.stub(page: 1, totalPages: 3, ids: 1...5)),
            2: .failure(.offline),
        ])
        await sut.onAppear()
        try await sut.scrollToTheEnd()

        try await sut.scrollToTheEnd()

        #expect(await repository.requestedPages == [1, 2])
    }

    @Test("Retrying a failed next page asks for it again")
    func retryingANextPageAsksAgain() async throws {
        let (sut, repository) = CharacterListViewModel.forTesting(pages: [
            1: .success(.stub(page: 1, totalPages: 3, ids: 1...5)),
            2: .failure(.offline),
        ])
        await sut.onAppear()
        try await sut.scrollToTheEnd()

        sut.retryNextPage()
        await sut.pagingTask?.value

        #expect(await repository.requestedPages == [1, 2, 2])
    }

    @Test("Retrying the first page asks for it again from the error screen")
    func retryingTheFirstPageAsksAgain() async {
        let (sut, repository) = CharacterListViewModel.forTesting(pages: [
            1: .failure(.timeout),
        ])
        await sut.onAppear()

        sut.retry()
        await sut.searchTask?.value

        #expect(await repository.requestedPages == [1, 1])
    }

    @Test("Coming back to a failed screen does not retry on its own")
    func appearingAgainOnAFailedScreenDoesNotRetry() async {
        // Retrying is the user's decision, made with their button. If returning to the
        // screen repeated the request, a sheet opening and closing over the error would
        // hammer a server that already said no.
        let (sut, repository) = CharacterListViewModel.forTesting(pages: [
            1: .failure(.timeout),
        ])

        await sut.onAppear()
        await sut.onAppear()

        #expect(sut.state == .failed(.timeout))
        #expect(await repository.requestedPages == [1])
    }

    @Test("Being cancelled is not failing: nothing is shown for it")
    func aCancelledLoadIsNotAFailure() async {
        // If the user left the screen while it was loading, there's nothing to report:
        // the error screen can't appear for a request that was cancelled on purpose
        let (sut, _) = CharacterListViewModel.forTesting(pages: [
            1: .failure(.cancelled),
        ])

        await sut.onAppear()

        #expect(sut.state == .loading)
    }

    @Test("A next page that was cancelled leaves no error in the footer")
    func aCancelledNextPageIsNotAFailure() async throws {
        let (sut, _) = CharacterListViewModel.forTesting(pages: [
            1: .success(.stub(page: 1, totalPages: 3, ids: 1...5)),
            2: .failure(.cancelled),
        ])
        await sut.onAppear()

        try await sut.scrollToTheEnd()

        #expect(sut.state.value?.map(\.id) == [1, 2, 3, 4, 5])
        #expect(sut.nextPageError == nil)
        #expect(!sut.isLoadingNextPage)
    }
}
