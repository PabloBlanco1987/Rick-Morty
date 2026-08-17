import Foundation

// Cumple el contrato CharacterRepository del dominio contra la API real
struct DefaultCharacterRepository: CharacterRepository {
    private let remote: CharacterRemoteDataSource

    init(remote: CharacterRemoteDataSource) {
        self.remote = remote
    }

    func characters(
        page: Int,
        filter: CharacterFilter,
        freshness: Freshness
    ) async throws(AppError) -> Page<Character> {
        do {
            let dto = try await remote.characters(page: page, filter: filter, freshness: freshness)
            return CharacterMapper.map(dto, page: page)
        } catch {
            // Cuando un filtro no encuentra nada, la API contesta 404 con un cuerpo de
            // error, no con un results vacío. Que no haya resultados es el resultado de
            // una búsqueda, no un fallo, así que lo traduzco aquí, que es la capa que
            // conoce las manías de esta API, y la UI enseña un estado vacío en vez de
            // una pantalla de error.
            if error == .notFound { return .empty(page: page) }
            throw error
        }
    }

    func character(id: Int) async throws(AppError) -> Character {
        // Aquí no traduzco el 404 a propósito: pedir un personaje que no existe sí es
        // un no encontrado de verdad, y la pantalla de detalle tiene que decirlo.
        CharacterMapper.map(try await remote.character(id: id))
    }

    func episodes(ids: [Int]) async throws(AppError) -> [Episode] {
        try await remote.episodes(ids: ids).map(EpisodeMapper.map)
    }
}
