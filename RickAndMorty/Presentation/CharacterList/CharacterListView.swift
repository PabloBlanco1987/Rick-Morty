import SwiftUI

// El listado de personajes.
// La vista no decide nada: pinta el estado que le da el view model y le devuelve los
// gestos. Todo el cuerpo es un switch exhaustivo sobre ViewState, así que si mañana
// aparece un estado nuevo el compilador señala este fichero en vez de dejar una
// pantalla en blanco en producción.
struct CharacterListView: View {
    @Bindable var viewModel: CharacterListViewModel

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var isShowingFilters = false

    var body: some View {
        content
            .navigationTitle("Characters")
            // La búsqueda es del servidor, no un filtrado de lo que ya está cargado:
            // buscar entre las veinte celdas que ha traído la primera página sería
            // buscar en el 2% de los personajes y decirle al usuario que no hay más.
            .searchable(text: $viewModel.searchText, prompt: "Search characters")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isShowingFilters = true
                    } label: {
                        // El icono relleno cuando hay filtros puestos: al volver a la
                        // pantalla es lo que explica por qué se están viendo doce
                        // personajes en vez de ochocientos
                        Label(
                            "Filters",
                            systemImage: viewModel.hasActiveFilters
                                ? "line.3.horizontal.decrease.circle.fill"
                                : "line.3.horizontal.decrease.circle"
                        )
                    }
                    .accessibilityLabel(viewModel.hasActiveFilters ? "Filters, active" : "Filters")
                }
            }
            .sheet(isPresented: $isShowingFilters) {
                CharacterFiltersView(viewModel: viewModel)
            }
            .task { await viewModel.onAppear() }
    }

    // @ViewBuilder y no AnyView: cada rama conserva su tipo, así que SwiftUI puede
    // seguir comparando vistas entre recomposiciones. AnyView le quitaría esa
    // información justo en la pantalla que más celdas tiene.
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
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(characters) { character in
                    // La navegación va por valor: la celda dice a qué personaje lleva y
                    // es RootView, que es quien conoce el grafo de dependencias, la que
                    // decide qué se construye con él. Así el listado no tiene que
                    // arrastrar el caso de uso del detalle sin usarlo para nada.
                    NavigationLink(value: character) {
                        CharacterCard(character: character)
                            .equatable()
                    }
                    .buttonStyle(.plain)
                    // El prefetch se dispara al aparecer, no al llegar al fondo:
                    // cuando el usuario ve la última fila, la página siguiente ya
                    // tiene que estar de camino.
                    .onAppear { viewModel.loadNextPageIfNeeded(after: character) }
                }
            }

            footer
        }
        .contentMargins(16, for: .scrollContent)
        .refreshable { await viewModel.refresh() }
    }

    @ViewBuilder
    private var footer: some View {
        if let error = viewModel.nextPageError {
            // El fallo de una página va aquí, debajo de lo que ya se ve, y no en una
            // pantalla de error: las páginas cargadas siguen siendo válidas.
            VStack(spacing: 12) {
                Text(error.title)
                    .font(.subheadline.weight(.semibold))
                Text(error.message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Try again") { viewModel.retryNextPage() }
                    .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        } else if viewModel.isLoadingNextPage {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .accessibilityLabel("Loading more characters")
        }
        // Cuando ya no quedan páginas no se pone nada. Un "no hay más" al final de una
        // lista de 826 personajes es ruido: que se acabe ya se ve.
    }

    private var columns: [GridItem] {
        // Con tamaños de accesibilidad el nombre necesita el ancho entero, así que el
        // grid pasa a una columna antes que recortar texto. Es adaptive y no un número
        // fijo de columnas para que el iPad y el modo horizontal salgan gratis.
        let minimum: CGFloat = dynamicTypeSize.isAccessibilitySize ? 280 : 150
        return [GridItem(.adaptive(minimum: minimum), spacing: 16)]
    }

    // MARK: - Estados

    // Vacío por una búsqueda y vacío de verdad no son el mismo estado para el usuario:
    // en el primero hay algo que hacer —quitar los filtros— y en el segundo no hay nada
    // que decir más que que no hay nada.
    @ViewBuilder
    private var emptyView: some View {
        if viewModel.hasActiveFilters {
            ContentUnavailableView {
                Label("No matches", systemImage: "magnifyingglass")
            } description: {
                Text("No characters match what you're looking for.")
            } actions: {
                Button("Clear filters") { viewModel.clearFilters() }
                    .buttonStyle(.borderedProminent)
            }
        } else {
            ContentUnavailableView(
                "No characters",
                systemImage: "person.slash",
                description: Text("There's nothing to show here yet.")
            )
        }
    }

    private var skeleton: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                // Ocho: las que caben en una pantalla larga. Menos dejaría un hueco
                // debajo que delataría que aún no hay nada.
                ForEach(0..<8, id: \.self) { _ in
                    CharacterCardSkeleton()
                }
            }
        }
        .contentMargins(16, for: .scrollContent)
        .scrollDisabled(true)
        .redacted(reason: .placeholder)
        // Para VoiceOver esto es una sola cosa que dice "cargando", no ocho celdas de
        // texto falso
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading characters")
    }

    private func errorView(_ error: AppError) -> some View {
        ContentUnavailableView {
            Label(error.title, systemImage: error.systemImage)
        } description: {
            Text(error.message)
        } actions: {
            Button("Try again") {
                Task { await viewModel.retry() }
            }
            .buttonStyle(.borderedProminent)
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
