import SwiftUI

@main
struct RickAndMortyApp: App {
    // El grafo de datos se monta una vez, aquí, y de aquí para abajo nadie vuelve a ver
    // un tipo concreto de la capa de datos
    private let dependencies = AppDependencies.forLaunch()

    var body: some Scene {
        WindowGroup {
            RootView(dependencies: dependencies)
        }
    }
}
