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

    // Las imágenes de la última página que ha llegado. La vista las precalienta mientras
    // el usuario todavía está leyendo la anterior, para que cuando baje hasta ellas las
    // celdas aparezcan ya con su imagen. Aquí solo se dice cuáles son: qué se hace con
    // ellas —y con qué caché— es cosa de la vista, que es quien tiene la caché a mano.
    // Son las de la última página y no todas las cargadas a propósito: lo que ya se ha
    // visto ya está en disco, y lo que hay que adelantar es lo que viene.
    private(set) var latestPageImageURLs: [URL] = []

    // Los criterios activos. Es de solo lectura desde fuera porque cambiarlos no es
    // asignar un valor: es tirar la lista, reiniciar la paginación y lanzar una
    // petición. Todo eso pasa por los accesos de abajo, que son los que la vista usa.
    private(set) var filter: CharacterFilter = .empty

    // internal y no private a propósito: los tests esperan a estas tareas para saber que
    // la carga ha terminado, en vez de dormir un rato y confiar.
    @ObservationIgnored private(set) var pagingTask: Task<Void, Never>?
    @ObservationIgnored private(set) var searchTask: Task<Void, Never>?

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

    // Lo que se espera desde la última tecla antes de preguntarle al servidor.
    //
    // La búsqueda es del servidor, así que sin esta espera escribir "rick" son cuatro
    // peticiones de las que solo importa la última: las tres primeras salen, gastan
    // conexión y llegan para ser descartadas. Trescientos cincuenta milisegundos es más
    // que la pausa entre dos teclas escribiendo de corrido y bastante menos de lo que se
    // percibe como que la app no responde.
    private static let searchDebounce: Duration = .milliseconds(350)

    init(
        fetchCharacters: FetchCharactersUseCase,
        // Inyectable para que los tests comprueben el freno sin dormir de verdad, igual
        // que ya se hace con RetryingHTTPClient
        sleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }
    ) {
        self.fetchCharacters = fetchCharacters
        self.sleep = sleep
    }

    // MARK: - Búsqueda y filtros

    // La vista bindea contra estos accesos y no contra `filter` directamente. Escribir
    // en ellos no deja el criterio guardado para luego: dispara la recarga que toca, y
    // cada uno sabe si lo suyo se teclea —y entonces hay que esperar a que el usuario
    // pare— o se toca una vez.
    var searchText: String {
        get { filter.name }
        set {
            let previous = filter.trimmedName
            filter.name = newValue
            // Añadir un espacio al final no es buscar otra cosa. Sin esta comparación,
            // la barra de búsqueda de iOS —que recorta y vuelve a escribir el texto al
            // perder el foco— acabaría repitiendo la misma petición.
            guard filter.trimmedName != previous else { return }
            reload(afterTyping: true)
        }
    }

    var speciesFilter: String {
        get { filter.species }
        set {
            let previous = filter.trimmedSpecies
            filter.species = newValue
            guard filter.trimmedSpecies != previous else { return }
            reload(afterTyping: true)
        }
    }

    // Estos dos se eligen de una lista, no se teclean: no hay ninguna tecla siguiente
    // que esperar, así que la petición sale ya
    var statusFilter: Character.Status? {
        get { filter.status }
        set {
            guard newValue != filter.status else { return }
            filter.status = newValue
            reload(afterTyping: false)
        }
    }

    var genderFilter: Character.Gender? {
        get { filter.gender }
        set {
            guard newValue != filter.gender else { return }
            filter.gender = newValue
            reload(afterTyping: false)
        }
    }

    // Los filtros de la hoja: estado, género y especie. La búsqueda va aparte a propósito
    // aunque para el dominio sea un criterio más: tiene su propio control —la barra— con
    // su propia forma de borrarse. Contarla aquí encendía el icono de filtros al teclear,
    // VoiceOver anunciaba "Filters, active" sin haber tocado un filtro, y el "Clear" de
    // la hoja borraba un texto que no está en la hoja.
    var hasActiveFilters: Bool {
        filter.status != nil || filter.gender != nil || !filter.trimmedSpecies.isEmpty
    }

    var hasSearchText: Bool { !filter.trimmedName.isEmpty }

    // Si la lista está acotada por algo, sea la búsqueda o los filtros. Es lo que separa
    // "no hay nada" de "no hay nada que encaje", que se cuentan distinto.
    var isNarrowed: Bool { !filter.isEmpty }

    // Lo que hace el "Clear" de la hoja: solo lo que está en la hoja
    func clearFilters() {
        guard hasActiveFilters else { return }
        filter.status = nil
        filter.gender = nil
        filter.species = ""
        reload(afterTyping: false)
    }

    // Lo que ofrece la pantalla vacía: quitar todo lo que acota, la búsqueda incluida
    func clearSearchAndFilters() {
        guard isNarrowed else { return }
        filter = .empty
        reload(afterTyping: false)
    }

    // Un cambio de criterio no es una página más: es otra lista. Se tira lo cargado, se
    // vuelve a la página uno y se cancela lo que hubiera en vuelo, porque una respuesta
    // de la búsqueda anterior que llegue tarde no puede acabar pintada bajo un filtro
    // que ya no es el que está puesto.
    private func reload(afterTyping: Bool) {
        searchTask?.cancel()
        pagingTask?.cancel()
        pagingTask = nil
        isLoadingNextPage = false
        nextPageError = nil
        lastPage = nil

        searchTask = Task { [weak self] in
            guard let self else { return }

            if afterTyping {
                await sleep(Self.searchDebounce)
                // Si mientras se esperaba ha llegado otra tecla, esta búsqueda ya no
                // vale: la ha reemplazado la siguiente y aquí no se pide nada
                guard !Task.isCancelled else { return }
            }

            await loadFirstPage(showingPlaceholder: true)
        }
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
    //
    // Y pide la página fresca a propósito: es la única carga que lo hace. La API sirve
    // las páginas con noventa días de caducidad, así que sin decirlo la primera página
    // saldría de la caché de red igual que la primera vez y el gesto no traería nada.
    // Refrescar es preguntarle al servidor si ha cambiado, aunque cueste una ida y vuelta.
    func refresh() async {
        searchTask?.cancel()
        searchTask = nil
        pagingTask?.cancel()
        pagingTask = nil
        isLoadingNextPage = false
        nextPageError = nil
        await loadFirstPage(showingPlaceholder: false, freshness: .fresh)
    }

    private func loadFirstPage(showingPlaceholder: Bool, freshness: Freshness = .acceptCached) async {
        if showingPlaceholder { state = .loading }

        // El filtro se lee aquí y se lleva hasta el final: si cambia mientras la
        // petición está en vuelo, lo que llegue se compara contra el que se pidió y no
        // contra el que haya puesto ahora.
        //
        // La comparación va por `normalized` porque tiene que usar el mismo criterio con
        // el que se decide recargar: escribir un espacio al final no dispara una petición
        // nueva, así que tampoco puede invalidar la que ya viene de camino. Comparando
        // los campos crudos, ese espacio tiraba una respuesta buena y dejaba la pantalla
        // en .loading sin nadie que la sacara de ahí.
        let requested = filter

        do {
            let page = try await fetchCharacters.execute(page: 1, filter: requested, freshness: freshness)
            guard !Task.isCancelled, requested.normalized == filter.normalized else { return }

            lastPage = page
            lastPageArrivedAt = .now
            loadedIDs = Set(page.items.map(\.id))
            nextPageError = nil
            latestPageImageURLs = page.items.compactMap(\.imageURL)
            apply(page.items)
        } catch {
            // Cancelar no es fallar: si el usuario se ha ido de la pantalla no hay
            // nada que contarle.
            guard error != .cancelled, requested.normalized == filter.normalized else { return }

            // Un refresh que falla no puede dejar sin lista al que ya la estaba
            // mirando. Se conserva lo que hay y no se enseña el error.
            //
            // Ese refresh fallido se queda hoy sin aviso: el usuario conserva la lista,
            // que es lo importante, pero no se entera de que lo que ve puede estar
            // viejo. Se deja así a sabiendas porque el sitio natural es un aviso
            // efímero, y montarlo bien —cola, tiempo de vida, que VoiceOver lo anuncie—
            // es una pieza en sí misma. Entraría como un modificador sobre
            // CharacterListView alimentado desde aquí. Ver README, "Límites conocidos".
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

        let requested = filter

        // El freno va aquí dentro y no en la guarda de arriba a propósito: si se
        // rechazara la petición en vez de retrasarla, no habría quien la volviera a
        // pedir. El .onAppear de una celda se dispara una sola vez, así que rechazar es
        // perder la página. Además, mientras se espera, isLoadingNextPage sigue puesto:
        // el usuario ve el indicador al final de la lista y el resto de celdas no puede
        // colar otra petición.
        await waitOutTheGapBetweenPages()
        guard !Task.isCancelled else { return }

        do {
            let result = try await fetchCharacters.execute(page: page, filter: requested)
            // Además del filtro, se comprueba que esta siga siendo la página que toca.
            // Un refresh conserva la lista mientras trae la primera página, así que sus
            // celdas del final siguen en pantalla y pueden pedir la siguiente —la 4, si
            // se iba por la 3— antes de que llegue la 1 nueva. Sin esta guarda esa página
            // aterrizaba sobre la lista ya sustituida: página 1 seguida de la 4, con la 2
            // y la 3 saltadas para siempre.
            guard !Task.isCancelled,
                  requested.normalized == filter.normalized,
                  lastPage?.nextPage == page
            else { return }
            lastPageArrivedAt = .now

            // La API pagina sobre una lista estable, así que en principio no repite.
            // Pero si dos páginas trajeran el mismo personaje, ForEach acabaría con dos
            // ids iguales y SwiftUI dejaría de saber qué celda es cuál: animaciones a
            // la celda equivocada y estado que salta de una a otra. Filtrar cuesta un
            // Set y lo cierra.
            let fresh = result.items.filter { loadedIDs.insert($0.id).inserted }
            lastPage = result
            latestPageImageURLs = fresh.compactMap(\.imageURL)
            apply((state.value ?? []) + fresh)
        } catch {
            guard error != .cancelled,
                  requested.normalized == filter.normalized,
                  lastPage?.nextPage == page
            else { return }
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
