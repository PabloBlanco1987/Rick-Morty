import Foundation
import Testing
@testable import RickAndMorty

/// Pull-to-refresh gets its own suite because its rule differs from every other load: it
/// replaces the list instead of appending to it, and a failure can't take the list down
/// with it. This covers that rule and what's exposed so the view can warn that what's on
/// screen might be stale.
@MainActor
@Suite("Character list refresh")
struct CharacterListRefreshTests {
    @Test("Refreshing replaces the list instead of appending to it")
    func refreshReplacesTheList() async throws {
        let (sut, repository) = CharacterListViewModel.forTesting(pages: [
            1: .success(.stub(page: 1, totalPages: 3, ids: 1...5)),
            2: .success(.stub(page: 2, totalPages: 3, ids: 6...10)),
        ])
        await sut.onAppear()
        try await sut.scrollToTheEnd()

        await sut.refresh()

        #expect(sut.state.value?.map(\.id) == [1, 2, 3, 4, 5])
        #expect(await repository.requestedPages == [1, 2, 1])
    }

    @Test("Only a refresh asks for fresh data; every other load settles for what is cached")
    func onlyARefreshAsksForFreshData() async throws {
        // Pages are served with a 90-day cache expiry, so without asking explicitly the
        // first page would come from the network cache same as the first time, and the
        // gesture would bring nothing. Conversely, if every other load asked for fresh
        // data, going back from the detail or paging would cost an unnecessary round trip.
        let (sut, repository) = CharacterListViewModel.forTesting(pages: [
            1: .success(.stub(page: 1, totalPages: 3, ids: 1...5)),
            2: .success(.stub(page: 2, totalPages: 3, ids: 6...10)),
        ])
        await sut.onAppear()
        try await sut.scrollToTheEnd()

        await sut.refresh()

        #expect(await repository.requestedFreshness == [.acceptCached, .acceptCached, .fresh])
    }

    @Test("While a refresh is in flight the list stays on screen, with no skeleton")
    func refreshKeepsTheListWhileLoading() async {
        // The refresh control itself is already the indicator; showing skeletons too
        // would hide the list the user has in front of them while pulling it down
        let gate = AsyncGate()
        let (sut, repository) = CharacterListViewModel.forTesting(pages: [
            1: .success(.stub(page: 1, totalPages: 3, ids: 1...5)),
        ])
        await sut.onAppear()

        await repository.holdListings(at: gate)
        let refreshing = Task { await sut.refresh() }
        await gate.waitUntilReached()

        #expect(sut.state.value?.map(\.id) == [1, 2, 3, 4, 5])

        await gate.open()
        await refreshing.value
    }

    @Test("A refresh that fails keeps the list the user was looking at, and says so")
    func refreshFailureKeepsTheList() async {
        // A refresh can fail; what it can't do is take away the list from someone who
        // already had it. An error screen here would punish the user for pulling down.
        // But a list that looks unchanged after refreshing looks fresh, so the failure
        // is exposed for the view to warn about.
        let (sut, repository) = CharacterListViewModel.forTesting(pages: [
            1: .success(.stub(page: 1, totalPages: 3, ids: 1...5)),
        ])
        await sut.onAppear()

        await repository.setCharacters(.failure(.offline), forPage: 1)
        await sut.refresh()

        #expect(sut.state.value?.map(\.id) == [1, 2, 3, 4, 5])
        #expect(sut.refreshFailure == .offline)
    }

    @Test("A refresh that fails with nothing on screen is a screen failure, not a notice")
    func refreshFailureWithoutAListOwnsTheScreen() async {
        // With no list to preserve there's nothing to warn about — the error owns the
        // screen, same as the first load
        let (sut, repository) = CharacterListViewModel.forTesting(pages: [
            1: .failure(.timeout),
        ])
        await sut.onAppear()

        await repository.setCharacters(.failure(.offline), forPage: 1)
        await sut.refresh()

        #expect(sut.state == .failed(.offline))
        #expect(sut.refreshFailure == nil)
    }

    @Test("Dismissing the refresh failure clears it and nothing else")
    func dismissingTheRefreshFailure() async {
        let (sut, repository) = CharacterListViewModel.forTesting(pages: [
            1: .success(.stub(page: 1, totalPages: 3, ids: 1...5)),
        ])
        await sut.onAppear()
        await repository.setCharacters(.failure(.offline), forPage: 1)
        await sut.refresh()

        sut.dismissRefreshFailure()

        #expect(sut.refreshFailure == nil)
        #expect(sut.state.value?.map(\.id) == [1, 2, 3, 4, 5])
    }

    @Test("A refresh that succeeds afterwards clears the failure: the list is fresh again")
    func aLaterSuccessfulRefreshClearsTheFailure() async {
        let (sut, repository) = CharacterListViewModel.forTesting(pages: [
            1: .success(.stub(page: 1, totalPages: 3, ids: 1...5)),
        ])
        await sut.onAppear()
        await repository.setCharacters(.failure(.offline), forPage: 1)
        await sut.refresh()

        await repository.setCharacters(.success(.stub(page: 1, totalPages: 3, ids: 1...5)), forPage: 1)
        await sut.refresh()

        #expect(sut.refreshFailure == nil)
    }

    @Test("Changing the criteria clears the failure: the list it warned about is gone")
    func aNewSearchClearsTheRefreshFailure() async {
        let (sut, repository) = CharacterListViewModel.forTesting(pages: [
            1: .success(.stub(page: 1, totalPages: 3, ids: 1...5)),
        ])
        await sut.onAppear()
        await repository.setCharacters(.failure(.offline), forPage: 1)
        await sut.refresh()

        await repository.setCharacters(.success(.stub(page: 1, totalPages: 1, ids: 1...2)), forPage: 1)
        sut.statusFilter = .dead
        await sut.searchTask?.value

        #expect(sut.refreshFailure == nil)
    }

    @Test("Refreshing clears a previous next page error")
    func refreshClearsTheNextPageError() async throws {
        let (sut, _) = CharacterListViewModel.forTesting(pages: [
            1: .success(.stub(page: 1, totalPages: 3, ids: 1...5)),
            2: .failure(.offline),
        ])
        await sut.onAppear()
        try await sut.scrollToTheEnd()

        await sut.refresh()

        #expect(sut.nextPageError == nil)
    }

    @Test("A refresh that fails because it was cancelled says nothing")
    func aCancelledRefreshIsNotAFailure() async {
        // Cancelling isn't failing — if the user left the screen mid-gesture, the list
        // doesn't change and there's no notice to see
        let (sut, repository) = CharacterListViewModel.forTesting(pages: [
            1: .success(.stub(page: 1, totalPages: 3, ids: 1...5)),
        ])
        await sut.onAppear()

        await repository.setCharacters(.failure(.cancelled), forPage: 1)
        await sut.refresh()

        #expect(sut.state.value?.map(\.id) == [1, 2, 3, 4, 5])
        #expect(sut.refreshFailure == nil)
    }

    // MARK: - Races

    @Test("A refresh cancels the page that was loading, and that page is thrown away")
    func refreshCancelsThePageInFlight() async throws {
        // A refresh replaces the whole list — a page that was in flight for the old list
        // can't land at the end of the new one. And the footer indicator switches off
        // immediately, not when that page arrives.
        let gate = AsyncGate()
        let (sut, repository) = CharacterListViewModel.forTesting(pages: [
            1: .success(.stub(page: 1, totalPages: 3, ids: 1...5)),
            2: .success(.stub(page: 2, totalPages: 3, ids: 6...10)),
        ])
        await sut.onAppear()

        await repository.holdListings(at: gate)
        sut.loadNextPageIfNeeded(after: try #require(sut.state.value?.last))
        await gate.waitUntilReached()
        let stalePage = sut.pagingTask

        await repository.holdListings(at: nil)
        await sut.refresh()
        #expect(!sut.isLoadingNextPage)

        await gate.open()
        await stalePage?.value

        #expect(sut.state.value?.map(\.id) == [1, 2, 3, 4, 5])
        #expect(!sut.isLoadingNextPage)
        #expect(sut.nextPageError == nil)
    }

    @Test("A page asked for during a refresh does not land on the refreshed list")
    func aPageAskedForDuringARefreshIsDiscarded() async throws {
        // A refresh keeps the list while fetching page 1, so its trailing cells stay on
        // screen and can request the next page — page 3, if it was on page 2 — before the
        // new page 1 arrives. Without the guard, that page would land on the
        // already-replaced list: page 1 followed by 3, with page 2 skipped forever.
        let gate = AsyncGate()
        let (sut, repository) = CharacterListViewModel.forTesting(pages: [
            1: .success(.stub(page: 1, totalPages: 3, ids: 1...5)),
            2: .success(.stub(page: 2, totalPages: 3, ids: 6...10)),
            3: .success(.stub(page: 3, totalPages: 3, ids: 11...15)),
        ])
        await sut.onAppear()
        try await sut.scrollToTheEnd()

        // The refresh is held while requesting page 1; meanwhile a trailing cell requests
        // page 3, which is also held. Both gates open, in either order — page 3 must
        // never land below page 1 either way.
        await repository.holdListings(at: gate)
        let refreshing = Task { await sut.refresh() }
        await gate.waitUntilReached()
        sut.loadNextPageIfNeeded(after: try #require(sut.state.value?.last))
        let latePage = sut.pagingTask
        await gate.open()
        await refreshing.value
        await latePage?.value

        #expect(sut.state.value?.map(\.id) == [1, 2, 3, 4, 5])

        // And the next page requested is 2, not 4 — pagination restarted
        try await sut.scrollToTheEnd()
        #expect(await repository.requestedPages.last == 2)
    }

    @Test("A refresh that comes back after the criteria changed is discarded, even if it failed")
    func aLateRefreshForOlderCriteriaIsDiscarded() async {
        // The refresh doesn't run inside the search task, so changing the criteria
        // doesn't cancel it — the filter comparison is what has to discard it. And if it
        // also failed, it must not leave the refresh notice on a list that isn't the one
        // it refreshed.
        let gate = AsyncGate()
        let (sut, repository) = CharacterListViewModel.forTesting(pages: [
            1: .success(.stub(page: 1, totalPages: 1, ids: 1...5)),
        ])
        await sut.onAppear()

        await repository.setCharacters(.failure(.offline), forPage: 1)
        await repository.holdListings(at: gate)
        let refreshing = Task { await sut.refresh() }
        await gate.waitUntilReached()

        await repository.holdListings(at: nil)
        await repository.setCharacters(.success(.stub(page: 1, totalPages: 1, ids: 100...102)), forPage: 1)
        sut.statusFilter = .dead
        await sut.searchTask?.value

        await gate.open()
        await refreshing.value

        #expect(sut.state.value?.map(\.id) == [100, 101, 102])
        #expect(sut.refreshFailure == nil)
    }

    @Test("A cancelled page that finishes late does not switch off the indicator of the page that replaced it")
    func aStalePageDoesNotClobberTheNewOne() async throws {
        // A refresh cancels the in-flight page and switches off the indicator right
        // away. If that page finished later and switched it off again, it would do so
        // on the load that replaced it — the footer would lose its indicator and another
        // cell could sneak in a second request for the same page.
        let stale = AsyncGate()
        let fresh = AsyncGate()
        let (sut, repository) = CharacterListViewModel.forTesting(pages: [
            1: .success(.stub(page: 1, totalPages: 3, ids: 1...5)),
            2: .success(.stub(page: 2, totalPages: 3, ids: 6...10)),
        ])
        await sut.onAppear()

        // Page 2 of the old list, held
        await repository.holdListings(at: stale)
        sut.loadNextPageIfNeeded(after: try #require(sut.state.value?.last))
        await stale.waitUntilReached()
        let stalePage = sut.pagingTask

        // The refresh cancels it and fetches page 1; then page 2 of the new list is
        // requested, and that's the one held now
        await repository.holdListings(at: nil)
        await sut.refresh()
        await repository.holdListings(at: fresh)
        sut.loadNextPageIfNeeded(after: try #require(sut.state.value?.last))
        await fresh.waitUntilReached()
        let freshPage = sut.pagingTask
        #expect(sut.isLoadingNextPage)

        // The stale one finishes late — it must not touch the new one's indicator
        await stale.open()
        await stalePage?.value
        #expect(sut.isLoadingNextPage, "The stale page switched off the indicator of the page that replaced it")

        await fresh.open()
        await freshPage?.value
        #expect(sut.state.value?.map(\.id) == [1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
        #expect(!sut.isLoadingNextPage)
    }
}
