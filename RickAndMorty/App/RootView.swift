import SwiftUI

/// Root of the view hierarchy.
///
/// Deliberately thin: builds the navigation container and the view model from the
/// already-composed graph. The only place a view knows `AppDependencies` exists —
/// every screen below gets just what it needs, nothing more.
struct RootView: View {

    // @State, not a plain property: the view model must survive re-renders.
    // Created inside body, it'd reset on every redraw, losing the list and paging.
    @State private var characterList: CharacterListViewModel
    private let dependencies: AppDependencies

    @MainActor
    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        _characterList = State(
            initialValue: CharacterListViewModel(fetchCharacters: dependencies.fetchCharacters)
        )
    }

    var body: some View {
        NavigationStack {
            CharacterListView(viewModel: characterList)
                // Value-based navigation, not views embedded in the link: the cell just
                // declares where it leads, and this screen — the only one that knows the
                // graph — decides what to build. Avoids threading detail dependencies
                // through the list and every cell.
                .navigationDestination(for: Character.self) { character in
                    CharacterDetailView(
                        character: character,
                        fetchCharacterDetail: dependencies.fetchCharacterDetail
                    )
                }
        }
    }
}

#Preview {
    RootView(dependencies: .live())
}
