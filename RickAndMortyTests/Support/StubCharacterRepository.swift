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
    private(set) var requestedCharacterIDs: [Int] = []

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
    // las seis anteriores. Lo que no esté en el diccionario sale como página vacía.
    init(
        charactersByPage: [Int: Result<Page<Character>, AppError>],
        character: Result<Character, AppError> = .success(.stub()),
        episodes: Result<[Episode], AppError> = .success([])
    ) {
        self.charactersByPage = charactersByPage
        self.charactersFallback = .success(.empty())
        self.characterResult = character
        self.episodesResult = episodes
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

    func characters(
        page: Int,
        filter: CharacterFilter,
        freshness: Freshness
    ) async throws(AppError) -> Page<Character> {
        requestedPages.append(page)
        requestedFilters.append(filter)
        return try (charactersByPage[page] ?? charactersFallback).get()
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
        status: Status = .alive,
        episodeIDs: [Int] = [1, 2]
    ) -> Character {
        Character(
            id: id,
            name: name,
            status: status,
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
            totalPages: totalPages,
            totalCount: totalPages * ids.count
        )
    }
}
