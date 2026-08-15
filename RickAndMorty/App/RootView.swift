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

    // Se guarda entero porque el destino de navegación se construye cuando el usuario
    // toca una celda, no al montar la pantalla, y para entonces hace falta el caso de
    // uso del detalle.
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
                // La navegación va por valor y no por vistas metidas dentro del enlace:
                // así la celda solo declara a dónde lleva y esta pantalla —la única que
                // conoce el grafo— decide qué se construye con ello. Es lo que evita
                // tener que arrastrar las dependencias del detalle a través del listado
                // y de cada celda.
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
