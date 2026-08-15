import SwiftUI

@main
struct RickAndMortyApp: App {
    // El grafo se monta una vez, aquí, y nadie más vuelve a ver un tipo concreto
    private let dependencies = AppDependencies.live()

    var body: some Scene {
        WindowGroup {
            RootView(dependencies: dependencies)
        }
    }
}
