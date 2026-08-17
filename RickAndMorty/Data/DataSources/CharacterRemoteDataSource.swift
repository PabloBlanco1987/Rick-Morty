import Foundation

// Sabe qué endpoints hay y con qué forma contesta cada uno. Nada más: aquí no cruza
// ningún tipo de dominio ni se decide nada sobre caché.
// Es un tipo aparte para que añadir soporte offline más adelante sea meter un
// LocalCharacterDataSource al lado y una política en el repositorio, en vez de tener
// que separar código de red de código de mapeo.
struct CharacterRemoteDataSource: Sendable {
    private let client: any HTTPClient

    init(client: any HTTPClient) {
        self.client = client
    }

    func characters(
        page: Int,
        filter: CharacterFilter,
        freshness: Freshness = .acceptCached
    ) async throws(AppError) -> PageDTO<CharacterDTO> {
        try await client.send(RickAndMortyAPI.characters(page: page, filter: filter, freshness: freshness))
    }

    func character(id: Int) async throws(AppError) -> CharacterDTO {
        try await client.send(RickAndMortyAPI.character(id: id))
    }

    // Absorbe el cambio de forma del endpoint de lote: /episode/1,2 devuelve un array
    // y /episode/1 un objeto suelto. Quien llame recibe siempre un array.
    func episodes(ids: [Int]) async throws(AppError) -> [EpisodeDTO] {
        guard !ids.isEmpty else { return [] }

        let endpoint = RickAndMortyAPI.episodes(ids: ids)

        guard ids.count > 1 else {
            let single = try await client.send(endpoint, as: EpisodeDTO.self)
            return [single]
        }

        return try await client.send(endpoint, as: [EpisodeDTO].self)
    }
}
