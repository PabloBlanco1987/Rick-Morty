import SwiftUI

@main
struct RickAndMortyApp: App {
    // The data graph is assembled once, here — nothing below ever sees a
    // concrete Data-layer type again.
    private let dependencies = AppDependencies.forLaunch()

    var body: some Scene {
        WindowGroup {
            RootView(dependencies: dependencies)
        }
    }
}
