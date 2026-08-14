import SwiftUI

/// Root of the view hierarchy.
///
/// Kept deliberately thin: its only job is to own the navigation container and
/// hand the composed dependency graph down to the feature views.
struct RootView: View {
    var body: some View {
        // TODO: [Phase 02] Replace with `CharacterListView`, injected from `AppDependencies`.
        ContentUnavailableView(
            "Rick & Morty",
            systemImage: "person.3.sequence",
            description: Text("The character browser lands in the next phase.")
        )
    }
}

#Preview {
    RootView()
}
