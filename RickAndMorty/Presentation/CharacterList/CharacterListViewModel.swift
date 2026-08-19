import Foundation
import Observation

/// The list's state and actions.
/// Doesn't import SwiftUI — not a style rule, it's proof that no view concerns have
/// leaked in here. What's here is a use case, a state, and some methods, so it can be
/// tested whole without spinning up a view hierarchy.
@MainActor
@Observable
final class CharacterListViewModel {
    private(set) var state: ViewState<[Character]> = .idle

    // Loading the next page isn't the same as loading the screen, so it's kept out of
    // `state`: the list stays loaded while the rest arrives, and this only lights up
    // the footer indicator.
    private(set) var isLoadingNextPage = false

    // And failing to load it isn't the same as failing the screen either. If page 7
    // fails, the six pages the user is already viewing are still valid — discarding
    // them for a full-screen error would punish them for scrolling. The failure shows
    // in the footer, with its own retry button.
    private(set) var nextPageError: AppError?

    // A pull-to-refresh that failed with the list still on screen. The list stays —
    // that's the point — and this is what tells the user what they see may be stale.
    // It's the error itself, not a flag, so the notice can say what happened. Cleared
    // by the next load that brings data, a filter change (which replaces the list it
    // was warning about), and the notice dismissing itself; how long it shows is up
    // to the view.
    private(set) var refreshFailure: AppError?

    // Images from the last page that arrived. The view prewarms them while the user is
    // still reading the previous page, so cells already have their image once scrolled
    // into view. This only states which URLs they are — what's done with them, and
    // which cache, is up to the view, which holds the cache. Deliberately just the
    // last page, not every loaded one: what's already been seen is already on disk;
    // what needs prefetching is what's coming.
    private(set) var latestPageImageURLs: [URL] = []

    // Active filter criteria. Read-only from outside because changing it isn't just
    // assigning a value — it means discarding the list, resetting pagination, and
    // firing a request. All of that goes through the accessors below, which is what
    // the view uses.
    private(set) var filter: CharacterFilter = .empty

    // internal, not private, on purpose: tests await these tasks to know loading
    // finished, instead of sleeping a while and hoping.
    @ObservationIgnored private(set) var pagingTask: Task<Void, Never>?
    @ObservationIgnored private(set) var searchTask: Task<Void, Never>?

    private let fetchCharacters: FetchCharactersUseCase

    // Metadata from the last page that arrived: this is where whether there's a next
    // page, and which one, comes from. No separate counter, because a counter and a
    // list can drift out of sync, and the page states it itself.
    private var lastPage: Page<Character>?

    // IDs already loaded, so the same character isn't added twice
    private var loadedIDs: Set<Character.ID> = []

    // The (already-trimmed) criteria that loaded what's on screen. Prevents reloading
    // the same thing: typing a letter and deleting it within the debounce, or
    // cancelling a search right after typing, returns to the criteria already
    // rendered, and re-requesting it would discard the list, show the skeleton, lose
    // scroll position, and spend a request to land exactly where it already was.
    private var loadedFilter: CharacterFilter?

    // IDs of the last loaded cells: the next page is requested when any of them
    // appears. A set, not an index, because a fast scroll can skip a specific cell's
    // `.onAppear`; with any one of the eight appearing, the request fires.
    private var prefetchTriggerIDs: Set<Character.ID> = []

    // Eight cells before the end. With a two- or three-column grid that's three to
    // four rows of margin: enough for the next page to arrive before the user hits
    // the bottom, not so much that pages nobody will look at get fetched.
    private static let prefetchDistance = 8

    // When the last page arrived, so the next one isn't requested right on top of it
    private var lastPageArrivedAt: ContinuousClock.Instant?
    private let sleep: @Sendable (Duration) async -> Void

    // The brake between pages.
    //
    // Without it, a fast gesture chains four or five pages in under a second: page 2
    // arrives, its cells appear while the finger's still moving, that requests page 3,
    // and so on. That's a hundred characters nobody will look at and, worse, a burst
    // of requests that earns a 429 from the API, which then takes down the load that
    // actually mattered.
    //
    // With the brake, a fast swipe hits the end of what's loaded, finds the indicator,
    // and waits. That's what any well-behaved infinite list does: scroll isn't
    // blocked — that feels broken — there's just no new content until there really is
    // some.
    private static let gapBetweenPages: Duration = .milliseconds(400)

    // Wait time since the last keystroke before asking the server.
    //
    // Search hits the server, so without this debounce, typing "rick" is four
    // requests where only the last one matters: the first three fire, spend
    // bandwidth, and land only to be discarded. 350 ms is more than the pause between
    // two keys typed at a normal pace and well under what reads as the app not
    // responding.
    private static let searchDebounce: Duration = .milliseconds(350)

    init(
        fetchCharacters: FetchCharactersUseCase,
        // Injectable so tests can verify the brake without actually sleeping, same as
        // RetryingHTTPClient already does
        sleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }
    ) {
        self.fetchCharacters = fetchCharacters
        self.sleep = sleep
    }

    // MARK: - Search and filters

    // The view binds to these accessors, not to `filter` directly. Writing to them
    // doesn't just save the criteria for later — it triggers the right reload, and
    // each one knows whether its value is typed (so it waits for the user to stop) or
    // set in one tap.
    var searchText: String {
        get { filter.name }
        set {
            let previous = filter.trimmedName
            filter.name = newValue
            // Adding a trailing space isn't searching for something else. Without
            // this comparison, iOS's search bar — which trims and rewrites the text
            // on losing focus — would end up repeating the same request.
            guard filter.trimmedName != previous else { return }
            reload(afterTyping: true)
        }
    }

    var speciesFilter: String {
        get { filter.species }
        set {
            let previous = filter.trimmedSpecies
            filter.species = newValue
            guard filter.trimmedSpecies != previous else { return }
            reload(afterTyping: true)
        }
    }

    // These two are picked from a list, not typed: there's no next keystroke to wait
    // for, so the request fires immediately
    var statusFilter: Character.Status? {
        get { filter.status }
        set {
            guard newValue != filter.status else { return }
            filter.status = newValue
            reload(afterTyping: false)
        }
    }

    var genderFilter: Character.Gender? {
        get { filter.gender }
        set {
            guard newValue != filter.gender else { return }
            filter.gender = newValue
            reload(afterTyping: false)
        }
    }

    // Sheet filters: status, gender, and species. Search is deliberately separate,
    // even though the domain treats it as just another criterion — it has its own
    // control, the search bar, with its own way to clear. Counting it here would
    // light up the filters icon while typing without touching a filter, and the
    // sheet's "Clear" would erase text that isn't on the sheet.
    var hasActiveFilters: Bool {
        filter.status != nil || filter.gender != nil || !filter.trimmedSpecies.isEmpty
    }

    var hasSearchText: Bool { !filter.trimmedName.isEmpty }

    // Whether the list is narrowed by anything, search or filters. This is what
    // separates "there's nothing" from "nothing matches", which read differently.
    var isNarrowed: Bool { !filter.isEmpty }

    // What the sheet's "Clear" does: only what's on the sheet
    func clearFilters() {
        guard hasActiveFilters else { return }
        filter.status = nil
        filter.gender = nil
        filter.species = ""
        reload(afterTyping: false)
    }

    // What the empty screen offers: clear everything narrowing the list, search included
    func clearSearchAndFilters() {
        guard isNarrowed else { return }
        filter = .empty
        reload(afterTyping: false)
    }

    // A criteria change isn't one more page — it's a different list. Discards what's
    // loaded, resets to page one, and cancels anything in flight, because a late
    // response from the previous search can't end up rendered under a filter that's
    // no longer set.
    //
    // But it discards only when it's time to request, not on every keystroke: the
    // previous list stays on screen through the debounce, and if the criteria end up
    // back where they were rendered — a letter typed then deleted, a search
    // cancelled — there's nothing to reload and everything stays put. A page the old
    // list requests during that window is harmless: if the criteria changed, it lands
    // on a different filter and gets discarded; if they're back to the same, it's a
    // valid page.
    private func reload(afterTyping: Bool) {
        searchTask?.cancel()

        searchTask = Task { [weak self] in
            guard let self else { return }

            if afterTyping {
                await sleep(Self.searchDebounce)
                // If another keystroke arrived while waiting, this search is stale —
                // the next one replaced it, and nothing gets requested here
                guard !Task.isCancelled else { return }
            }

            guard !isShowingList(for: filter) else { return }

            pagingTask?.cancel()
            pagingTask = nil
            isLoadingNextPage = false
            nextPageError = nil
            // The list it was warning about goes away with the skeleton: so does the notice
            refreshFailure = nil
            lastPage = nil
            await loadFirstPage(showingPlaceholder: true)
        }
    }

    // Whether what's on screen — list or empty, both are valid results — is already
    // the answer to this criteria
    private func isShowingList(for filter: CharacterFilter) -> Bool {
        guard filter.normalized == loadedFilter else { return false }
        switch state {
        case .loaded, .empty: return true
        case .idle, .loading, .failed: return false
        }
    }

    // MARK: - Screen

    // Called by the view's `.task`. Only loads the first time: `.task` re-fires every
    // time the view appears, and returning from the detail screen can't mean
    // discarding the list and the pages that already cost their scroll.
    func onAppear() async {
        guard case .idle = state else { return }
        await loadFirstPage(showingPlaceholder: true)
    }

    // Retrying from the error screen means restarting the list with the same
    // criteria, so it goes through the same path as a filter change: the view model
    // creates and owns the task, like the others, instead of a loose Task on the
    // button that nothing could cancel
    func retry() {
        reload(afterTyping: false)
    }

    // Pull to refresh. Doesn't set `.loading` because the refresh control itself is
    // already the indicator; also showing the skeletons would cover the list the
    // user has in front of them while pulling it.
    //
    // Deliberately requests a fresh page: the only load that does. The API serves
    // pages with a 90-day expiry, so without asking for fresh data, the first page
    // would come straight from the network cache just like the first time and the
    // gesture would bring back nothing. Refreshing means asking the server if
    // anything changed, even at the cost of a round trip.
    func refresh() async {
        searchTask?.cancel()
        searchTask = nil
        pagingTask?.cancel()
        pagingTask = nil
        isLoadingNextPage = false
        nextPageError = nil
        await loadFirstPage(showingPlaceholder: false, freshness: .fresh)
    }

    // Called by the refresh-failure notice when the user taps it or its time runs
    // out. A method, not a binding over `refreshFailure`, so the only way to set it
    // stays a refresh actually failing.
    func dismissRefreshFailure() {
        refreshFailure = nil
    }

    private func loadFirstPage(showingPlaceholder: Bool, freshness: Freshness = .acceptCached) async {
        if showingPlaceholder { state = .loading }

        // The filter is read here and carried through to the end: if it changes
        // while the request is in flight, what arrives is compared against what was
        // requested, not against whatever is set now.
        //
        // Compared via `normalized` because it has to use the same criteria that
        // decides whether to reload: a trailing space doesn't trigger a new request,
        // so it can't invalidate the one already in flight either. Comparing raw
        // fields, that space would discard a good response and leave the screen
        // stuck in `.loading` with nothing to pull it out.
        let requested = filter

        do {
            let page = try await fetchCharacters.execute(page: 1, filter: requested, freshness: freshness)
            guard !Task.isCancelled, requested.normalized == filter.normalized else { return }

            lastPage = page
            lastPageArrivedAt = .now
            loadedIDs = Set(page.items.map(\.id))
            loadedFilter = requested.normalized
            nextPageError = nil
            // Data arrived, so what's on screen is no longer stale
            refreshFailure = nil
            latestPageImageURLs = page.items.compactMap(\.imageURL)
            apply(page.items)
        } catch {
            // Cancelling isn't failing: if the user has left the screen there's
            // nothing to tell them.
            guard error != .cancelled, requested.normalized == filter.normalized else { return }

            // A failed refresh can't leave the person already viewing the list
            // without one: what's there is kept and the error doesn't take over the
            // screen. What it does do is warn, because a list that stays unchanged
            // after being pulled looks fresh without being it. This is the only load
            // that can reach this point with a list still on screen — the others
            // already swapped it for the skeleton.
            guard state.value == nil else {
                refreshFailure = error
                return
            }
            state = .failed(error)
        }
    }

    // MARK: - Pagination

    // The infinite-scroll entry point, called by a cell's `.onAppear`. Deliberately
    // synchronous: so the view model creates and owns the task, and it's the one
    // that knows to cancel it when a refresh arrives. If the view created it with a
    // loose Task, nothing could stop it.
    func loadNextPageIfNeeded(after character: Character) {
        guard prefetchTriggerIDs.contains(character.id) else { return }
        loadNextPage()
    }

    // After a failure it must be requested manually. Otherwise the trailing cells
    // keep appearing, keep re-triggering the load, and the same error retries in a
    // loop against a server that already said no.
    func retryNextPage() {
        nextPageError = nil
        loadNextPage()
    }

    private func loadNextPage() {
        // The check and the flag are adjacent and synchronous: no `await` between
        // checking and setting, so two cells appearing in the same layout pass can't
        // sneak in two requests for the same page.
        guard !isLoadingNextPage,
              nextPageError == nil,
              let nextPage = lastPage?.nextPage
        else { return }

        isLoadingNextPage = true
        pagingTask = Task { [weak self] in
            await self?.appendPage(nextPage)
        }
    }

    private func appendPage(_ page: Int) async {
        defer {
            // Only if this is still the current load. One that got cancelled — by a
            // refresh or a criteria change — was already retired by whoever
            // cancelled it, and by then another page may be in flight in its place:
            // turning off the indicator here would turn off that other one's, and
            // let a cell sneak in a second request for the same page.
            if !Task.isCancelled {
                isLoadingNextPage = false
                pagingTask = nil
            }
        }

        let requested = filter

        // The brake lives here, not in the guard above, on purpose: rejecting the
        // request instead of delaying it would leave nobody to ask again. A cell's
        // `.onAppear` fires only once, so rejecting means losing the page. Also,
        // while waiting, `isLoadingNextPage` stays set: the user sees the indicator
        // at the list's end, and no other cell can sneak in another request.
        await waitOutTheGapBetweenPages()
        guard !Task.isCancelled else { return }

        do {
            let result = try await fetchCharacters.execute(page: page, filter: requested)
            // Besides the filter, checks this is still the page that's due. A
            // refresh keeps the list while fetching the first page, so its trailing
            // cells stay on screen and can request the next one — page 4, if it was
            // on page 3 — before the new page 1 arrives. Without this guard, that
            // page would land on the already-replaced list: page 1 followed by 4,
            // with 2 and 3 skipped forever.
            guard !Task.isCancelled,
                  requested.normalized == filter.normalized,
                  lastPage?.nextPage == page
            else { return }
            lastPageArrivedAt = .now

            // The API paginates over a stable list, so it shouldn't repeat in
            // principle. But if two pages did bring the same character, ForEach
            // would end up with duplicate ids and SwiftUI would lose track of which
            // cell is which: animations landing on the wrong cell, state jumping
            // between them. Filtering costs one Set and closes it off.
            let fresh = result.items.filter { loadedIDs.insert($0.id).inserted }
            lastPage = result
            latestPageImageURLs = fresh.compactMap(\.imageURL)
            apply((state.value ?? []) + fresh)
        } catch {
            guard error != .cancelled,
                  requested.normalized == filter.normalized,
                  lastPage?.nextPage == page
            else { return }
            nextPageError = error
        }
    }

    private func waitOutTheGapBetweenPages() async {
        guard let lastPageArrivedAt else { return }

        let sinceLastPage = ContinuousClock.now - lastPageArrivedAt
        guard sinceLastPage < Self.gapBetweenPages else { return }

        await sleep(Self.gapBetweenPages - sinceLastPage)
    }

    private func apply(_ characters: [Character]) {
        state = characters.isEmpty ? .empty : .loaded(characters)
        prefetchTriggerIDs = Set(characters.suffix(Self.prefetchDistance).map(\.id))
    }
}
