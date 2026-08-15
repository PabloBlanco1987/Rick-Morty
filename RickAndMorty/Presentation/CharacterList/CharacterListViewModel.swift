import Foundation
import Observation

// El estado y las acciones del listado.
// No importa SwiftUI: no es una regla de estilo, es la comprobación de que aquí no se
// ha colado nada de la vista. Lo que hay es un caso de uso, un estado y unos métodos,
// y por eso se puede probar entero sin arrancar una jerarquía de vistas.
@MainActor
@Observable
final class CharacterListViewModel {
    private(set) var state: ViewState<[Character]> = .idle

    // Cargar la página siguiente no es lo mismo que cargar la pantalla, así que no
    // entra en `state`: la lista sigue estando cargada mientras llega lo que falta, y
    // esto solo enciende el indicador del pie.
    private(set) var isLoadingNextPage = false

    // Y fallar al cargarla tampoco es lo mismo que fallar la pantalla. Si se cae la
    // página 7, las seis que el usuario ya está viendo siguen siendo válidas: tirarlas
    // para enseñar un error a pantalla completa sería castigarle por haber hecho
    // scroll. El fallo se cuenta en el pie, con su botón de reintentar.
    private(set) var nextPageError: AppError?

    // internal y no private a propósito: los tests esperan a esta tarea para saber que
    // la carga ha terminado. Es lo que permite que la suite no tenga ni un sleep.
    @ObservationIgnored private(set) var pagingTask: Task<Void, Never>?

    private let fetchCharacters: FetchCharactersUseCase

    // Metadatos de la última página que ha llegado: de aquí sale si queda siguiente y
    // cuál es. No se guarda un contador aparte porque un contador y una lista pueden
    // desincronizarse, y la página lo dice ella misma.
    private var lastPage: Page<Character>?

    // Los ids ya cargados, para no meter el mismo personaje dos veces
    private var loadedIDs: Set<Character.ID> = []

    // Los ids de las últimas celdas cargadas: al aparecer cualquiera de ellas se pide
    // la página siguiente. Es un conjunto y no un índice porque un scroll rápido
    // puede saltarse el .onAppear de una celda concreta; con que aparezca una de las
    // ocho, la petición sale.
    private var prefetchTriggerIDs: Set<Character.ID> = []

    // Ocho celdas antes del final. Con un grid de dos o tres columnas son entre tres y
    // cuatro filas de margen: bastante para que la página siguiente llegue antes de
    // que el usuario toque el fondo, y no tanto como para acabar trayendo páginas que
    // nadie va a mirar.
    private static let prefetchDistance = 8

    // Cuándo llegó la última página, para no pedir la siguiente pegada a ella
    private var lastPageArrivedAt: ContinuousClock.Instant?
    private let sleep: @Sendable (Duration) async -> Void

    // El freno entre páginas.
    //
    // Sin él, un gesto rápido encadena cuatro o cinco páginas en menos de un segundo:
    // llega la página 2, sus celdas aparecen mientras el dedo sigue en marcha, eso pide
    // la 3, y vuelta a empezar. Son cien personajes que nadie va a mirar y, sobre todo,
    // una ráfaga de peticiones que se gana un 429 de la API, que a su vez tumba la
    // carga que sí importaba.
    //
    // Con el freno, un vistazo rápido llega al final de lo cargado, se encuentra el
    // indicador y espera. Es lo que hace cualquier lista infinita que se porte bien: no
    // se bloquea el scroll —eso se siente roto—, simplemente no hay contenido nuevo
    // hasta que lo haya de verdad.
    private static let gapBetweenPages: Duration = .milliseconds(400)

    init(
        fetchCharacters: FetchCharactersUseCase,
        // Inyectable para que los tests comprueben el freno sin dormir de verdad, igual
        // que ya se hace con RetryingHTTPClient
        sleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }
    ) {
        self.fetchCharacters = fetchCharacters
        self.sleep = sleep
    }

    // MARK: - Pantalla

    // La llama el .task de la vista. Solo carga la primera vez: .task se vuelve a
    // disparar cada vez que la vista aparece, y volver del detalle no puede significar
    // tirar la lista y las páginas que ya costaron su scroll.
    func onAppear() async {
        guard case .idle = state else { return }
        await loadFirstPage(showingPlaceholder: true)
    }

    func retry() async {
        await loadFirstPage(showingPlaceholder: true)
    }

    // Pull to refresh. No pone .loading porque el propio control de refresco ya es el
    // indicador; enseñar además los esqueletos sería tapar la lista que el usuario
    // tiene delante mientras tira de ella.
    func refresh() async {
        pagingTask?.cancel()
        pagingTask = nil
        isLoadingNextPage = false
        nextPageError = nil
        await loadFirstPage(showingPlaceholder: false)
    }

    private func loadFirstPage(showingPlaceholder: Bool) async {
        if showingPlaceholder { state = .loading }

        do {
            let page = try await fetchCharacters.execute(page: 1)
            lastPage = page
            lastPageArrivedAt = .now
            loadedIDs = Set(page.items.map(\.id))
            nextPageError = nil
            apply(page.items)
        } catch {
            // Cancelar no es fallar: si el usuario se ha ido de la pantalla no hay
            // nada que contarle.
            guard error != .cancelled else { return }

            // Un refresh que falla no puede dejar sin lista al que ya la estaba
            // mirando. Se conserva lo que hay y no se enseña el error.
            //
            // TODO: [Fase 04] Ese refresh fallido se queda hoy sin aviso: el usuario
            // conserva la lista, que es lo importante, pero no se entera de que lo que
            // ve puede estar viejo. No se hace ahora porque el sitio natural es un
            // aviso efímero, y montarlo bien —cola, tiempo de vida, que VoiceOver lo
            // anuncie— es una pieza en sí misma que además hace falta para los
            // filtros. Entraría como un modificador sobre CharacterListView alimentado
            // desde aquí.
            guard state.value == nil else { return }
            state = .failed(error)
        }
    }

    // MARK: - Paginación

    // El punto de entrada del scroll infinito, que llama el .onAppear de una celda.
    // Es síncrono a propósito: así la tarea la crea y la posee el view model, que es
    // quien sabe cancelarla cuando llega un refresh. Si la creara la vista con un Task
    // suelto, nadie tendría forma de pararla.
    func loadNextPageIfNeeded(after character: Character) {
        guard prefetchTriggerIDs.contains(character.id) else { return }
        loadNextPage()
    }

    // Después de un fallo hace falta pedirlo a mano. Si no, las celdas del final
    // siguen apareciendo, vuelven a disparar la carga y el mismo error se reintenta en
    // bucle contra un servidor que ya ha dicho que no.
    func retryNextPage() {
        nextPageError = nil
        loadNextPage()
    }

    private func loadNextPage() {
        // La comprobación y el flag van pegados y son síncronos: entre mirar y marcar
        // no hay ni un await, así que dos celdas que aparecen en el mismo ciclo de
        // layout no pueden colar dos peticiones de la misma página.
        guard !isLoadingNextPage,
              nextPageError == nil,
              let nextPage = lastPage?.nextPage
        else { return }

        isLoadingNextPage = true
        pagingTask = Task { [weak self] in
            await self?.appendPage(nextPage)
        }
    }

    private func appendPage(_ page: Int) async {
        defer {
            isLoadingNextPage = false
            pagingTask = nil
        }

        // El freno va aquí dentro y no en la guarda de arriba a propósito: si se
        // rechazara la petición en vez de retrasarla, no habría quien la volviera a
        // pedir. El .onAppear de una celda se dispara una sola vez, así que rechazar es
        // perder la página. Además, mientras se espera, isLoadingNextPage sigue puesto:
        // el usuario ve el indicador al final de la lista y el resto de celdas no puede
        // colar otra petición.
        await waitOutTheGapBetweenPages()
        guard !Task.isCancelled else { return }

        do {
            let result = try await fetchCharacters.execute(page: page)
            guard !Task.isCancelled else { return }
            lastPageArrivedAt = .now

            // La API pagina sobre una lista estable, así que en principio no repite.
            // Pero si dos páginas trajeran el mismo personaje, ForEach acabaría con dos
            // ids iguales y SwiftUI dejaría de saber qué celda es cuál: animaciones a
            // la celda equivocada y estado que salta de una a otra. Filtrar cuesta un
            // Set y lo cierra.
            let fresh = result.items.filter { loadedIDs.insert($0.id).inserted }
            lastPage = result
            apply((state.value ?? []) + fresh)
        } catch {
            guard error != .cancelled else { return }
            nextPageError = error
        }
    }

    private func waitOutTheGapBetweenPages() async {
        guard let lastPageArrivedAt else { return }

        let sinceLastPage = ContinuousClock.now - lastPageArrivedAt
        guard sinceLastPage < Self.gapBetweenPages else { return }

        await sleep(Self.gapBetweenPages - sinceLastPage)
    }

    private func apply(_ characters: [Character]) {
        state = characters.isEmpty ? .empty : .loaded(characters)
        prefetchTriggerIDs = Set(characters.suffix(Self.prefetchDistance).map(\.id))
    }
}
