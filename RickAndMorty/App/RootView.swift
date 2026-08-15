import SwiftUI

// Raíz de la jerarquía de vistas.
// La dejo fina a propósito: monta el contenedor de navegación y construye el view
// model a partir del grafo ya compuesto. Es el único punto donde la vista sabe que
// AppDependencies existe; de aquí para abajo cada pantalla recibe lo suyo y nada más.
struct RootView: View {
    // @State y no una propiedad normal: el view model tiene que sobrevivir a las
    // recomposiciones. Si se creara en el body, cada redibujado tiraría la lista y
    // volvería a empezar por la página uno.
    @State private var characterList: CharacterListViewModel

    @MainActor
    init(dependencies: AppDependencies) {
        _characterList = State(
            initialValue: CharacterListViewModel(fetchCharacters: dependencies.fetchCharacters)
        )
    }

    var body: some View {
        NavigationStack {
            CharacterListView(viewModel: characterList)
        }
    }
}

#Preview {
    RootView(dependencies: .live())
}
