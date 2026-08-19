import Foundation
import Observation

/// State and actions for the detail screen. Unlike the list, this screen is reached
/// from a cell that already had the full character, so waiting on the server to show a
/// name the previous screen already had would be a fake wait: the known character is
/// kept aside and the header paints on the first frame — only the episodes are actually
/// fetched. The full detail is still requested by id, not just episodes, so the screen
/// keeps working if it's ever reached without one — a deep link, a notification.
@MainActor
@Observable
final class CharacterDetailViewModel {
    private(set) var state: ViewState<CharacterDetail> = .idle

    // What was already known on navigation. Optional because the view model doesn't
    // assume it's always reached from the list.
    private let knownCharacter: Character?

    private let characterID: Int
    private let fetchCharacterDetail: FetchCharacterDetailUseCase

    init(
        characterID: Int,
        known knownCharacter: Character? = nil,
        fetchCharacterDetail: FetchCharacterDetailUseCase
    ) {
        self.characterID = characterID
        self.knownCharacter = knownCharacter
        self.fetchCharacterDetail = fetchCharacterDetail
    }

    // What paints the header. Loaded wins over known: if the server says the character
    // moved since the list loaded, the new value stands.
    var character: Character? {
        state.value?.character ?? knownCharacter
    }

    // Episodes exist only once the detail arrives. Kept separate from `state` because
    // the view treats them as their own section — the header is already up while
    // they're still loading.
    var episodes: [Episode] {
        state.value?.episodes ?? []
    }

    // A failure with the character already on screen isn't the same as a blank
    // failure: the first drops a section, the second drops the whole screen.
    var hasContentOnScreen: Bool {
        character != nil
    }

    // Called by the view's .task, and only loads the first time. Not for returning
    // from another screen — the detail is the top of the stack and gets destroyed on
    // pop — but so the rule matches the list and holds up to anything that could
    // reappear the view without recreating it: a deep link, a sheet on top, a split
    // view on iPad.
    func onAppear() async {
        guard case .idle = state else { return }
        await load()
    }

    func retry() async {
        await load()
    }

    private func load() async {
        state = .loading

        do {
            let detail = try await fetchCharacterDetail.execute(id: characterID)
            // Leaving the screen mid-load can't leave a late write on a view that's
            // no longer there.
            guard !Task.isCancelled else { return }
            state = .loaded(detail)
        } catch {
            // Cancelling isn't failing: if the user went back, there's nothing to
            // tell them.
            guard error != .cancelled else { return }
            state = .failed(error)
        }
    }
}
