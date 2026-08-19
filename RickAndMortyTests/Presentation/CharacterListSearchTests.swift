import Foundation
import Testing
@testable import RickAndMorty

/// Search and filters get their own suite because they test something different from
/// pagination: that suite checks how the list grows, this one checks how it gets fully
/// replaced and what reaches the server when it does.
@MainActor
@Suite("Character list search and filters")
struct CharacterListSearchTests {
    // MARK: - Search

    @Test("Typing waits for the user to stop before asking the server")
    func searchWaitsForTheTypingToSettle() async {
        // Search hits the server — without this wait, typing "rick" is four requests
        // where only the last one matters.
        let waits = SleepRecorder()
        let repository = StubCharacterRepository(characters: .success(.stub(page: 1, totalPages: 1, ids: 1...3)))
        let sut = CharacterListViewModel.forTesting(repository, recordingWaitsInto: waits)
        await sut.onAppear()

        sut.searchText = "rick"
        await sut.searchTask?.value

        #expect(await waits.durations == [.milliseconds(350)])
        #expect(await repository.requestedSearchTerms == ["", "rick"])
    }

    @Test("A keystroke during the wait cancels the search that was waiting; only the last one goes out")
    func onlyTheLastKeystrokeIsSearched() async {
        // What actually happens while typing: the "ric" search is still debouncing when
        // "k" arrives, and it's cancelled before going out, so the server only sees the
        // full term. The wait is held on a gate so the second keystroke arrives while the
        // first search is genuinely waiting, not before it has even started.
        let debounce = AsyncGate()
        let repository = StubCharacterRepository(characters: .success(.stub(page: 1, totalPages: 1, ids: 1...3)))
        let sut = CharacterListViewModel(
            fetchCharacters: FetchCharactersUseCase(repository: repository),
            sleep: { _ in await debounce.wait() }
        )
        await sut.onAppear()

        sut.searchText = "ric"
        await debounce.waitUntilReached()
        sut.searchText = "rick"
        await debounce.open()
        await sut.searchTask?.value

        #expect(await repository.requestedSearchTerms == ["", "rick"])
    }

    @Test("Trailing whitespace is not a new search")
    func whitespaceDoesNotTriggerASearch() async {
        // iOS's search bar rewrites the text when it loses focus. Without comparing the
        // trimmed term, that would trigger another identical request.
        let repository = StubCharacterRepository(characters: .success(.stub(page: 1, totalPages: 1, ids: 1...3)))
        let sut = CharacterListViewModel.forTesting(repository)
        await sut.onAppear()
        sut.searchText = "rick"
        await sut.searchTask?.value

        sut.searchText = "rick "
        await sut.searchTask?.value

        #expect(await repository.requestedPages == [1, 1])
    }

    @Test("A search with no matches is an empty state, not an error")
    func emptySearchResult() async {
        let repository = StubCharacterRepository(
            charactersByPage: [1: .success(.stub(page: 1, totalPages: 1, ids: 1...3))]
        )
        let sut = CharacterListViewModel.forTesting(repository)
        await sut.onAppear()

        await repository.setCharacters(.success(.empty()), forPage: 1)
        sut.searchText = "zzzz"
        await sut.searchTask?.value

        #expect(sut.state == .empty)
        #expect(sut.isNarrowed)
    }

    @Test("Typing a letter and deleting it within the wait asks for nothing")
    func typingAndDeletingWithinTheWaitDoesNotReload() async {
        // By the end of the wait the criteria is back to what's already on screen, so
        // there's nothing to reload — re-requesting would discard the list, show the
        // skeleton, lose the scroll position, and spend a request just to end up back
        // where it started
        let repository = StubCharacterRepository(characters: .success(.stub(page: 1, totalPages: 1, ids: 1...3)))
        let sut = CharacterListViewModel.forTesting(repository)
        await sut.onAppear()

        sut.searchText = "r"
        sut.searchText = ""
        await sut.searchTask?.value

        #expect(await repository.requestedPages == [1])
        #expect(sut.state.value?.count == 3)
    }

    @Test("Typing a search does not light up the filters, but it does narrow the list")
    func searchIsNotAFilter() async {
        // Search has its own bar and its own way of clearing. Counting it as a filter
        // would light up the sheet's icon just from typing, without touching a filter,
        // and the sheet's "Clear" would erase text that isn't even in the sheet.
        let repository = StubCharacterRepository(characters: .success(.stub(page: 1, totalPages: 1, ids: 1...3)))
        let sut = CharacterListViewModel.forTesting(repository)
        await sut.onAppear()

        sut.searchText = "rick"
        await sut.searchTask?.value

        #expect(sut.hasSearchText)
        #expect(!sut.hasActiveFilters)
        #expect(sut.isNarrowed)
    }

    @Test("A search that lands after the user typed something else is not painted")
    func aLateResponseForAnOlderSearchIsDiscarded() async {
        // onlyTheLastKeystrokeIsSearched covers the case where the first search never
        // even goes out. Here it does go out, and arrives late: the "rick" response is
        // held, "morty" goes out and renders, and when "rick" finally arrives it must
        // not replace the response that's already correct.
        let gate = AsyncGate()
        let repository = StubCharacterRepository(
            charactersByPage: [1: .success(.stub(page: 1, totalPages: 1, ids: 1...3))]
        )
        let sut = CharacterListViewModel.forTesting(repository)
        await sut.onAppear()

        await repository.holdListings(at: gate)
        sut.searchText = "rick"
        await gate.waitUntilReached()
        let stale = sut.searchTask

        await repository.holdListings(at: nil)
        await repository.setCharacters(.success(.stub(page: 1, totalPages: 1, ids: 100...101)), forPage: 1)
        sut.searchText = "morty"
        await sut.searchTask?.value
        #expect(sut.state.value?.map(\.id) == [100, 101])

        await gate.open()
        await stale?.value

        #expect(await repository.requestedSearchTerms == ["", "rick", "morty"])
        #expect(sut.state.value?.map(\.id) == [100, 101])
    }

    @Test("A page that arrives after the criteria changed does not land on the new list")
    func aLatePageForAnOlderCriterionIsDiscarded() async throws {
        // Page two of the unfiltered list is still in flight when the user picks a
        // filter. If it landed, it would stick to the end of the filtered list: 20
        // characters that don't match the filter, appended below the 3 that do.
        let gate = AsyncGate()
        let repository = StubCharacterRepository(charactersByPage: [
            1: .success(.stub(page: 1, totalPages: 3, ids: 1...5)),
            2: .success(.stub(page: 2, totalPages: 3, ids: 6...10)),
        ])
        let sut = CharacterListViewModel.forTesting(repository)
        await sut.onAppear()

        await repository.holdListings(at: gate)
        sut.loadNextPageIfNeeded(after: try #require(sut.state.value?.last))
        await gate.waitUntilReached()
        let stalePage = sut.pagingTask

        await repository.holdListings(at: nil)
        await repository.setCharacters(.success(.stub(page: 1, totalPages: 1, ids: 100...102)), forPage: 1)
        sut.statusFilter = .dead
        await sut.searchTask?.value
        #expect(sut.state.value?.map(\.id) == [100, 101, 102])

        await gate.open()
        await stalePage?.value

        #expect(sut.state.value?.map(\.id) == [100, 101, 102])
        #expect(!sut.isLoadingNextPage)
    }

    // MARK: - Filters

    @Test("Typing a species waits for the user to stop, like the search does")
    func speciesWaitsForTheTypingToSettle() async {
        // Species is typed, not picked from a list — without the wait, "Human" would be
        // five requests where only the last one matters
        let waits = SleepRecorder()
        let repository = StubCharacterRepository(characters: .success(.stub(page: 1, totalPages: 1, ids: 1...3)))
        let sut = CharacterListViewModel.forTesting(repository, recordingWaitsInto: waits)
        await sut.onAppear()

        sut.speciesFilter = "Human"
        await sut.searchTask?.value

        #expect(await waits.durations == [.milliseconds(350)])
        #expect(await repository.requestedFilters.map(\.trimmedSpecies) == ["", "Human"])
        #expect(sut.hasActiveFilters)
    }

    @Test("Choosing a filter asks the server straight away, with no typing to wait for")
    func filtersDoNotWait() async {
        // A filter is tapped once, not typed — there's no next keystroke to wait for, so
        // making the user wait would be latency for nothing.
        let waits = SleepRecorder()
        let repository = StubCharacterRepository(characters: .success(.stub(page: 1, totalPages: 1, ids: 1...3)))
        let sut = CharacterListViewModel.forTesting(repository, recordingWaitsInto: waits)
        await sut.onAppear()

        sut.statusFilter = .alive
        await sut.searchTask?.value

        #expect(await waits.durations.isEmpty)
        #expect(await repository.requestedFilters.last?.status == .alive)
    }

    @Test("Every active criterion reaches the repository together")
    func criteriaTravelTogether() async {
        let repository = StubCharacterRepository(characters: .success(.stub(page: 1, totalPages: 1, ids: 1...3)))
        let sut = CharacterListViewModel.forTesting(repository)
        await sut.onAppear()

        sut.statusFilter = .alive
        await sut.searchTask?.value
        sut.genderFilter = .female
        await sut.searchTask?.value
        sut.speciesFilter = "Human"
        await sut.searchTask?.value

        let last = await repository.requestedFilters.last
        #expect(last?.status == .alive)
        #expect(last?.gender == .female)
        #expect(last?.trimmedSpecies == "Human")
    }

    @Test("A new filter replaces the list instead of appending to it")
    func filteringStartsTheListOver() async throws {
        // Filtering isn't one more page — it's a different list. If what was loaded
        // weren't discarded, the user would end up seeing results from two different
        // searches mixed together.
        let repository = StubCharacterRepository(charactersByPage: [
            1: .success(.stub(page: 1, totalPages: 3, ids: 1...5)),
            2: .success(.stub(page: 2, totalPages: 3, ids: 6...10)),
        ])
        let sut = CharacterListViewModel.forTesting(repository)
        await sut.onAppear()
        try await sut.scrollToTheEnd()
        #expect(sut.state.value?.count == 10)

        await repository.setCharacters(.success(.stub(page: 1, totalPages: 1, ids: 100...102)), forPage: 1)
        sut.statusFilter = .dead
        await sut.searchTask?.value

        #expect(sut.state.value?.map(\.id) == [100, 101, 102])
    }

    @Test("The next page is asked for with the filter that is active")
    func paginationKeepsTheFilter() async throws {
        // If page two went out without the filter, scrolling would end up bringing the
        // whole list in below a search — a result the user never asked for.
        let repository = StubCharacterRepository(charactersByPage: [
            1: .success(.stub(page: 1, totalPages: 3, ids: 1...5)),
            2: .success(.stub(page: 2, totalPages: 3, ids: 6...10)),
        ])
        let sut = CharacterListViewModel.forTesting(repository)
        await sut.onAppear()
        sut.statusFilter = .alive
        await sut.searchTask?.value

        try await sut.scrollToTheEnd()

        #expect(await repository.requestedFilters.last?.status == .alive)
        #expect(await repository.requestedPages == [1, 1, 2])
    }

    @Test("Clearing the filters keeps the search and asks the server again")
    func clearingFiltersReloads() async {
        // Search isn't a sheet filter — it has its own bar and its own way of clearing,
        // so "Clear" must not take it down with it
        let repository = StubCharacterRepository(characters: .success(.stub(page: 1, totalPages: 1, ids: 1...3)))
        let sut = CharacterListViewModel.forTesting(repository)
        await sut.onAppear()
        sut.searchText = "rick"
        sut.statusFilter = .alive
        await sut.searchTask?.value

        sut.clearFilters()
        await sut.searchTask?.value

        #expect(!sut.hasActiveFilters)
        #expect(await repository.requestedFilters.last == CharacterFilter(name: "rick"))
    }

    @Test("Clearing filters that were already empty asks for nothing")
    func clearingNothingDoesNothing() async {
        // The clear button still exists even with nothing set; tapping it must not cost
        // a full list reload.
        let repository = StubCharacterRepository(characters: .success(.stub(page: 1, totalPages: 1, ids: 1...3)))
        let sut = CharacterListViewModel.forTesting(repository)
        await sut.onAppear()

        sut.clearFilters()
        await sut.searchTask?.value

        #expect(await repository.requestedPages == [1])
    }

    @Test("The empty screen's action clears the search and the filters together and asks again")
    func clearingSearchAndFiltersReloadsWithNothing() async {
        // This is what the empty screen offers: clear everything narrowing the list,
        // search included, and return to the full list
        let repository = StubCharacterRepository(characters: .success(.stub(page: 1, totalPages: 1, ids: 1...3)))
        let sut = CharacterListViewModel.forTesting(repository)
        await sut.onAppear()
        sut.searchText = "rick"
        sut.statusFilter = .alive
        sut.speciesFilter = "Human"
        await sut.searchTask?.value

        sut.clearSearchAndFilters()
        await sut.searchTask?.value

        #expect(!sut.isNarrowed)
        #expect(sut.searchText.isEmpty)
        #expect(await repository.requestedFilters.last == .empty)
    }

    @Test("Clearing search and filters when nothing narrows the list asks for nothing")
    func clearingSearchAndFiltersWhenNothingIsNarrowedDoesNothing() async {
        let repository = StubCharacterRepository(characters: .success(.stub(page: 1, totalPages: 1, ids: 1...3)))
        let sut = CharacterListViewModel.forTesting(repository)
        await sut.onAppear()

        sut.clearSearchAndFilters()
        await sut.searchTask?.value

        #expect(await repository.requestedPages == [1])
    }

    @Test("A refresh keeps the filter the user is looking at")
    func refreshKeepsTheFilter() async {
        let repository = StubCharacterRepository(characters: .success(.stub(page: 1, totalPages: 1, ids: 1...3)))
        let sut = CharacterListViewModel.forTesting(repository)
        await sut.onAppear()
        sut.searchText = "rick"
        await sut.searchTask?.value

        await sut.refresh()

        #expect(await repository.requestedSearchTerms == ["", "rick", "rick"])
    }
}
