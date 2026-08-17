import OSLog
import SwiftUI

// El listado de personajes.
// La vista no decide nada: pinta el estado que le da el view model y le devuelve los
// gestos. Todo el cuerpo es un switch exhaustivo sobre ViewState, así que si mañana
// aparece un estado nuevo el compilador señala este fichero en vez de dejar una
// pantalla en blanco en producción.
struct CharacterListView: View {
    @Bindable var viewModel: CharacterListViewModel

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // La misma caché que usan las celdas: desde aquí se le adelantan las imágenes de la
    // página que acaba de llegar y se le retiene la red mientras el scroll va lanzado
    @Environment(\.imageCache) private var imageCache

    @State private var isShowingFilters = false

    // A partir de qué velocidad una deceleración cuenta como fling y no como un flick
    // para seguir leyendo. Un flick suave decelera durante un segundo mientras el
    // usuario ya está mirando las celdas nuevas: pausar ahí sería dejarlas grises justo
    // cuando las mira. Un fling de verdad pasa por dos o tres pantallas que nadie ve.
    //
    // La unidad de `ScrollPhaseChangeContext.velocity` no está documentada; medida en el
    // simulador es puntos por milisegundo, igual que en UIKit: un fling fuerte sale a
    // ~5,5 y un flick de lectura no llega a 1. Dos separa los dos gestos con margen. La
    // traza de abajo se queda para volver a mirarlo si un día cambia.
    private static let flingVelocity: CGFloat = 2

    var body: some View {
        content
            .navigationTitle(.characterListTitle)
            // La búsqueda es del servidor, no un filtrado de lo que ya está cargado:
            // buscar entre las veinte celdas que ha traído la primera página sería
            // buscar en el 2% de los personajes y decirle al usuario que no hay más.
            .searchable(text: $viewModel.searchText, prompt: .characterListSearchPrompt)
            // Por lo mismo que en el campo de especie: la API compara por texto, así que
            // el corrector solo cambia lo que el usuario ha escrito a propósito —"squanchy"
            // no es una palabra— y la mayúscula automática no aporta nada a una búsqueda
            // que no distingue mayúsculas
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isShowingFilters = true
                    } label: {
                        // El icono relleno cuando hay filtros puestos: al volver a la
                        // pantalla es lo que explica por qué se están viendo doce
                        // personajes en vez de ochocientos
                        Label(
                            .characterListFiltersButtonTitle,
                            systemImage: viewModel.hasActiveFilters
                                ? "line.3.horizontal.decrease.circle.fill"
                                : "line.3.horizontal.decrease.circle"
                        )
                    }
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
                    // El identificador para los tests de UI va en el enlace, que es el
                    // botón que XCTest toca, y no en la celda de dentro
                    .accessibilityIdentifier("character-\(character.id)")
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
        // El aviso de refresco fallido, entre el título y la rejilla: es donde estaba el
        // indicador de refresco del que viene. Como inset del área segura y no como
        // overlay porque el título grande flota sobre el contenido y un overlay quedaba
        // debajo de él; así el aviso tiene su franja y la rejilla se aparta los segundos
        // que dura. Solo existe con la lista delante, que es la única pantalla desde la
        // que se puede refrescar.
        .safeAreaInset(edge: .top, spacing: 0) {
            if let error = viewModel.refreshFailure {
                RefreshFailureNotice(error: error) { viewModel.dismissRefreshFailure() }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        // Con "reducir movimiento" el aviso aparece y se va sin animar, igual que el
        // fundido de las imágenes: la regla de la app es no mover nada, ni siquiera un
        // desvanecido, cuando el usuario ha pedido que no se mueva.
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: viewModel.refreshFailure)
        // Precalienta la página que acaba de llegar mientras el usuario lee la anterior.
        // Con id: cuando llega otra página se cancela el calentamiento de la anterior y
        // arranca el suyo, así que un fling que encadena páginas solo calienta la última,
        // que es hacia donde va el usuario. Un cambio de filtro cambia las URLs y cancela
        // igual. Lo que ya está en disco no cuesta nada.
        .task(id: viewModel.latestPageImageURLs) {
            await imageCache.warm(viewModel.latestPageImageURLs)
        }
        // Mientras el scroll va lanzado no sale nada a la red: cada petición de un fling
        // es cupo gastado en una celda que ya no está cuando llega, y es el cupo que le
        // falta a la pantalla donde se aterriza. Lo que ya está en memoria o en disco
        // sigue apareciendo. Es el scrollViewDidEndDecelerating de toda la vida.
        .onScrollPhaseChange { _, phase, context in
            setNetworkPaused(isFlinging(phase, context))
        }
        // Si la rejilla se va en mitad de un fling —un filtro que la sustituye por el
        // esqueleto— nadie llegaría a levantar la pausa. La cola además la caduca sola;
        // esto es el cinturón y aquello los tirantes.
        .onDisappear { setNetworkPaused(false) }
    }

    private func isFlinging(_ phase: ScrollPhase, _ context: ScrollPhaseChangeContext) -> Bool {
        guard phase == .decelerating, let velocity = context.velocity else { return false }
        let speed = abs(velocity.dy)
        #if DEBUG
        Self.scrollLog.debug("Decelerating at \(speed, privacy: .public)")
        #endif
        return speed > Self.flingVelocity
    }

    private func setNetworkPaused(_ paused: Bool) {
        Task { await imageCache.setNetworkPaused(paused) }
    }

    #if DEBUG
    private static let scrollLog = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "RickAndMorty",
        category: "Scroll"
    )
    #endif

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
                Button(.characterListRetryButton) { viewModel.retryNextPage() }
                    .buttonStyle(.bordered)
            }
            // Sobre el contenedor y no solo sobre el mensaje: con tamaños de
            // accesibilidad el título también se parte en dos líneas
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        } else if viewModel.isLoadingNextPage {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
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
    // en el primero hay algo que hacer —quitar lo que acota— y en el segundo no hay nada
    // que decir más que que no hay nada.
    @ViewBuilder
    private var emptyView: some View {
        if viewModel.isNarrowed {
            ContentUnavailableView {
                Label(.characterListNoMatchesTitle, systemImage: "magnifyingglass")
            } description: {
                Text(.characterListNoMatchesDescription)
            } actions: {
                // El botón dice lo que va a quitar: ofrecer "quitar los filtros" a quien
                // solo ha tecleado una búsqueda es ofrecerle deshacer algo que no hizo
                Button(clearNarrowingTitle) { viewModel.clearSearchAndFilters() }
                    .buttonStyle(.borderedProminent)
            }
        } else {
            ContentUnavailableView(
                .characterListEmptyTitle,
                systemImage: "person.slash",
                description: Text(.characterListEmptyDescription)
            )
        }
    }

    private var clearNarrowingTitle: LocalizedStringResource {
        switch (viewModel.hasSearchText, viewModel.hasActiveFilters) {
        case (true, true): .characterListClearSearchAndFiltersButton
        case (true, false): .characterListClearSearchButton
        default: .characterListClearFiltersButton
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
    }

    private func errorView(_ error: AppError) -> some View {
        ContentUnavailableView {
            Label(error.title, systemImage: error.systemImage)
        } description: {
            Text(error.message)
        } actions: {
            Button(.characterListRetryButton) { viewModel.retry() }
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
