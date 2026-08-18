import Foundation
@testable import RickAndMorty

// CharacterRepository con resultados preparados, para probar los casos de uso sin
// nada que se parezca a una red
actor StubCharacterRepository: CharacterRepository {
    private var charactersByPage: [Int: Result<Page<Character>, AppError>]
    private let charactersFallback: Result<Page<Character>, AppError>
    private let characterResult: Result<Character, AppError>
    private var episodesResult: Result<[Episode], AppError>

    private(set) var requestedEpisodeIDs: [[Int]] = []
    private(set) var requestedPages: [Int] = []
    // Con qué criterios se ha pedido cada listado: es lo que distingue una búsqueda que
    // llega al servidor de una que se queda filtrando en el móvil lo poco que ya tenía
    private(set) var requestedFilters: [CharacterFilter] = []
    // Y con cuánta frescura: es lo que distingue un pull to refresh, que tiene que
    // revalidar, de las demás cargas, que se conforman con lo guardado
    private(set) var requestedFreshness: [Freshness] = []
    private(set) var requestedCharacterIDs: [Int] = []

    // Si está puesto, cada listado se para aquí antes de contestar. Es lo que deja tener
    // una petición congelada en vuelo mientras el test cambia el criterio, refresca o
    // pide otra página, y comprobar después qué se hace con una respuesta que llega
    // tarde. Solo se apunta el listado: el detalle y los episodios no tienen carreras
    // que probar.
    private var gate: AsyncGate?

    var episodesCallCount: Int { requestedEpisodeIDs.count }
    var requestedSearchTerms: [String] { requestedFilters.map(\.trimmedName) }

    init(
        characters: Result<Page<Character>, AppError> = .success(.empty()),
        character: Result<Character, AppError> = .success(.stub()),
        episodes: Result<[Episode], AppError> = .success([])
    ) {
        self.charactersByPage = [:]
        self.charactersFallback = characters
        self.characterResult = character
        self.episodesResult = episodes
    }

    // Una respuesta distinta por página, que es lo que hace falta para probar la
    // paginación: acumular la dos sobre la uno, o que la siete falle sin que se caigan
    // las seis anteriores. Lo que no esté en el diccionario sale como página vacía. Solo
    // el listado: quien pagina no pide detalles ni episodios.
    init(charactersByPage: [Int: Result<Page<Character>, AppError>]) {
        self.charactersByPage = charactersByPage
        self.charactersFallback = .success(.empty())
        self.characterResult = .success(.stub())
        self.episodesResult = .success([])
    }

    // Cambia lo que se va a contestar de aquí en adelante, para probar lo que pasa
    // cuando algo que iba bien empieza a fallar: un refresh que se cae después de
    // haber cargado la lista, por ejemplo
    func setCharacters(_ result: Result<Page<Character>, AppError>, forPage page: Int) {
        charactersByPage[page] = result
    }

    // Lo mismo para los episodios, que es lo que hace falta para probar que un
    // reintento se recupera: primero se cae y a la segunda contesta
    func setEpisodes(_ result: Result<[Episode], AppError>) {
        episodesResult = result
    }

    // A partir de aquí los listados se quedan parados en el pestillo hasta que el test lo
    // abra; con nil, los siguientes vuelven a contestar al momento y solo los que ya
    // están parados esperan. Se apunta la petición antes de pararse, así el test puede
    // esperar a que haya llegado con `gate.waitUntilReached()` y saber que está
    // congelada dentro.
    func holdListings(at gate: AsyncGate?) {
        self.gate = gate
    }

    func characters(
        page: Int,
        filter: CharacterFilter,
        freshness: Freshness
    ) async throws(AppError) -> Page<Character> {
        requestedPages.append(page)
        requestedFilters.append(filter)
        requestedFreshness.append(freshness)
        // La respuesta se decide al entrar y no al salir del pestillo: así el test puede
        // cambiar lo que se contesta a partir de ahora sin cambiar lo que ya está en vuelo,
        // que es lo que hace falta para distinguir una respuesta vieja de una nueva
        let result = charactersByPage[page] ?? charactersFallback
        await gate?.wait()
        return try result.get()
    }

    func character(id: Int) async throws(AppError) -> Character {
        requestedCharacterIDs.append(id)
        return try characterResult.get()
    }

    func episodes(ids: [Int]) async throws(AppError) -> [Episode] {
        requestedEpisodeIDs.append(ids)
        return try episodesResult.get()
    }
}

extension Character {
    // Un personaje válido, del que cada test solo sobrescribe lo que le importa
    static func stub(
        id: Int = 1,
        name: String = "Rick Sanchez",
        episodeIDs: [Int] = [1, 2]
    ) -> Character {
        Character(
            id: id,
            name: name,
            status: .alive,
            species: "Human",
            type: nil,
            gender: .male,
            origin: "Earth (C-137)",
            location: "Citadel of Ricks",
            // Un avatar por id, como en la API: así un test puede distinguir las
            // imágenes de una página de las de la siguiente
            imageURL: URL(string: "https://rickandmortyapi.com/api/character/avatar/\(id).jpeg"),
            episodeIDs: episodeIDs
        )
    }
}

extension Page where Item == Character {
    // Una página con personajes de ids correlativos, para no escribir veinte stubs a
    // mano cada vez que se prueba el scroll
    static func stub(page: Int, totalPages: Int, ids: ClosedRange<Int>) -> Page<Character> {
        Page(
            items: ids.map { Character.stub(id: $0, name: "Character \($0)") },
            currentPage: page,
            totalPages: totalPages
        )
    }
}
