import SwiftUI

// Raíz de la jerarquía de vistas.
// La dejo fina a propósito: solo monta el contenedor de navegación y pasa hacia
// abajo el grafo de dependencias ya compuesto.
struct RootView: View {
    var body: some View {
        // TODO: [Fase 02] Sustituir por CharacterListView, inyectada desde AppDependencies
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
