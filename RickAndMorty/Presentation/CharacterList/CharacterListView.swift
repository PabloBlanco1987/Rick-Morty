import OSLog
import SwiftUI

/// The character list.
/// The view decides nothing: it renders the state the view model gives it and hands
/// back gestures. The whole body is an exhaustive switch over `ViewState`, so if a new
/// state appears later, the compiler flags this file instead of leaving a blank
/// screen in production.
struct CharacterListView: View {
    @Bindable var viewModel: CharacterListViewModel

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // Same cache the cells use: prefetches images for the page that just arrived, and
    // holds off network while the scroll is flinging
    @Environment(\.imageCache) private var imageCache

    @State private var isShowingFilters = false

    // Velocity threshold above which deceleration counts as a fling, not a reading
    // flick. A gentle flick decelerates for about a second while the user is already
    // looking at the new cells — pausing there would leave them grey right as they're
    // viewed. A real fling passes through two or three screens nobody sees.
    //
    // The unit of `ScrollPhaseChangeContext.velocity` isn't documented; measured on the
    // simulator it's points per millisecond, same as UIKit — a strong fling hits ~5.5,
    // a reading flick stays under 1. 2 separates the two gestures with margin. The
    // debug log below stays in case this needs revisiting.
    private static let flingVelocity: CGFloat = 2

    var body: some View {
        content
            .navigationTitle(.characterListTitle)
            // Search hits the server, not a filter over what's already loaded:
            // searching the twenty cells from the first page alone would search 2% of
            // the characters and tell the user there's nothing else.
            .searchable(text: $viewModel.searchText, prompt: .characterListSearchPrompt)
            // Same as the species field: the API matches by exact text, so autocorrect
            // only distorts what the user typed on purpose — "squanchy" isn't a word —
            // and auto-capitalization adds nothing to a search that's case-insensitive
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isShowingFilters = true
                    } label: {
                        // Filled icon when filters are active: on returning to the
                        // screen, it's what explains why twelve characters are
                        // showing instead of eight hundred
                        Label(
                            .characterListFiltersButtonTitle,
                            systemImage: viewModel.hasActiveFilters
                                ? "line.3.horizontal.decrease.circle.fill"
                                : "line.3.horizontal.decrease.circle"
                        )
                    }
                }
            }
            .sheet(isPresented: $isShowingFilters) {
                CharacterFiltersView(viewModel: viewModel)
            }
            .task { await viewModel.onAppear() }
    }

    // @ViewBuilder, not AnyView: each branch keeps its type, so SwiftUI can keep
    // diffing views across recompositions. AnyView would erase that on the screen
    // with the most cells.
    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            skeleton
        case .loaded(let characters):
            grid(characters)
        case .empty:
            emptyView
        case .failed(let error):
            errorView(error)
        }
    }

    // MARK: - Grid

    private func grid(_ characters: [Character]) -> some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: Theme.Layout.gridSpacing) {
                ForEach(characters) { character in
                    // Navigation is value-based: the cell says which character it
                    // leads to, and RootView, which owns the dependency graph, decides
                    // what gets built with it. This way the list doesn't have to carry
                    // the detail use case around unused.
                    NavigationLink(value: character) {
                        CharacterCard(character: character)
                            .equatable()
                    }
                    .buttonStyle(.plain)
                    // UI test identifier goes on the link, the button XCTest taps, not
                    // on the cell inside
                    .accessibilityIdentifier("character-\(character.id)")
                    // Prefetch fires on appear, not on reaching the bottom: by the
                    // time the user sees the last row, the next page already needs to
                    // be on its way.
                    .onAppear { viewModel.loadNextPageIfNeeded(after: character) }
                }
            }

            footer
        }
        .contentMargins(Theme.Layout.screenMargin, for: .scrollContent)
        .refreshable { await viewModel.refresh() }
        // Refresh-failure notice sits between title and grid, where the refresh
        // spinner used to be. A safe-area inset, not an overlay, because the large
        // title floats above content and an overlay would sit under it; this way the
        // notice gets its own strip and the grid steps aside for as long as it lasts.
        // Only exists with the list on screen, the only screen refresh happens from.
        .safeAreaInset(edge: .top, spacing: 0) {
            if let error = viewModel.refreshFailure {
                RefreshFailureNotice(error: error) { viewModel.dismissRefreshFailure() }
                    .padding(.horizontal, Theme.Layout.screenMargin)
                    .padding(.bottom, Theme.Spacing.small)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        // With "reduce motion" the notice appears and disappears without animating,
        // same as the image fade: the app's rule is to move nothing, not even a fade,
        // once the user has asked for no motion.
        .animation(Theme.Motion.notice(reduceMotion: reduceMotion), value: viewModel.refreshFailure)
        // Prewarms the page that just arrived while the user reads the previous one.
        // Keyed by id: a new page cancels the previous warm-up and starts its own, so
        // a fling that chains pages only warms the last one, which is where the user
        // is heading. A filter change swaps the URLs and cancels the same way.
        // Whatever's already on disk costs nothing.
        .task(id: viewModel.latestPageImageURLs) {
            await imageCache.warm(viewModel.latestPageImageURLs)
        }
        // Nothing goes out to the network while the scroll is flinging: every request
        // during a fling spends bandwidth on a cell that's gone by the time it lands,
        // bandwidth the screen it settles on then lacks. What's already in memory or
        // on disk still shows. This is the old scrollViewDidEndDecelerating.
        .onScrollPhaseChange { _, phase, context in
            setNetworkPaused(isFlinging(phase, context))
        }
        // If the grid disappears mid-fling — a filter swapping it for the skeleton —
        // nothing would ever lift the pause. The cache also expires it on its own;
        // this is belt, that's suspenders.
        .onDisappear { setNetworkPaused(false) }
    }

    private func isFlinging(_ phase: ScrollPhase, _ context: ScrollPhaseChangeContext) -> Bool {
        guard phase == .decelerating, let velocity = context.velocity else { return false }
        let speed = abs(velocity.dy)
        #if DEBUG
        Self.scrollLog.debug("Decelerating at \(speed, privacy: .public)")
        #endif
        return speed > Self.flingVelocity
    }

    private func setNetworkPaused(_ paused: Bool) {
        Task { await imageCache.setNetworkPaused(paused) }
    }

    #if DEBUG
    private static let scrollLog = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "RickAndMorty",
        category: "Scroll"
    )
    #endif

    @ViewBuilder
    private var footer: some View {
        if let error = viewModel.nextPageError {
            // A page failure goes here, below what's already showing, not as an error
            // screen: loaded pages are still valid. Same card the detail screen uses
            // when episodes fail, for the same reason: what's on screen still holds
            // and only a part failed.
            InlineErrorView(error: error, retryTitle: .characterListRetryButton) {
                viewModel.retryNextPage()
            }
            .padding(.vertical, Theme.Spacing.xLarge)
        } else if viewModel.isLoadingNextPage {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.xLarge)
        }
        // Nothing shows once there are no more pages. A "no more results" at the end
        // of an 826-character list is noise — it's already obvious it ended.
    }

    private var columns: [GridItem] {
        // At accessibility sizes the name needs the full width, so the grid drops to
        // one column rather than clip text. Adaptive, not a fixed column count, so
        // iPad and landscape come for free.
        let minimum = dynamicTypeSize.isAccessibilitySize
            ? Theme.Layout.accessibilityGridMinimumColumnWidth
            : Theme.Layout.gridMinimumColumnWidth
        return [GridItem(.adaptive(minimum: minimum), spacing: Theme.Layout.gridSpacing)]
    }

    // MARK: - States

    // Empty from a search and truly empty aren't the same state to the user: the
    // first has something to do — clear what's narrowing it — the second has nothing
    // to say beyond there being nothing.
    @ViewBuilder
    private var emptyView: some View {
        if viewModel.isNarrowed {
            ContentUnavailableView {
                Label(.characterListNoMatchesTitle, systemImage: "magnifyingglass")
            } description: {
                Text(.characterListNoMatchesDescription)
            } actions: {
                // The button says exactly what it'll clear: offering "clear filters"
                // to someone who only typed a search offers to undo something they
                // never did
                Button(clearNarrowingTitle) { viewModel.clearSearchAndFilters() }
                    .buttonStyle(.borderedProminent)
            }
        } else {
            ContentUnavailableView(
                .characterListEmptyTitle,
                systemImage: "person.slash",
                description: Text(.characterListEmptyDescription)
            )
        }
    }

    private var clearNarrowingTitle: LocalizedStringResource {
        switch (viewModel.hasSearchText, viewModel.hasActiveFilters) {
        case (true, true): .characterListClearSearchAndFiltersButton
        case (true, false): .characterListClearSearchButton
        default: .characterListClearFiltersButton
        }
    }

    private var skeleton: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: Theme.Layout.gridSpacing) {
                ForEach(0..<Theme.Layout.skeletonCardCount, id: \.self) { _ in
                    CharacterCardSkeleton()
                }
            }
        }
        .contentMargins(Theme.Layout.screenMargin, for: .scrollContent)
        .scrollDisabled(true)
        .redacted(reason: .placeholder)
    }

    private func errorView(_ error: AppError) -> some View {
        ErrorStateView(error: error, retryTitle: .characterListRetryButton) {
            viewModel.retry()
        }
    }
}

#Preview {
    NavigationStack {
        CharacterListView(
            viewModel: CharacterListViewModel(
                fetchCharacters: AppDependencies.live().fetchCharacters
            )
        )
    }
}
