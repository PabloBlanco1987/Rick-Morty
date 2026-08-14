import Foundation

// Monta los datos de la pantalla de detalle: el personaje y sus episodios.
// Aquí es donde un caso de uso aporta algo frente a llamar al repositorio a pelo,
// porque las dos peticiones se coordinan en este sitio y no en el view model.
struct FetchCharacterDetailUseCase: Sendable {
    private let repository: any CharacterRepository

    init(repository: any CharacterRepository) {
        self.repository = repository
    }

    func execute(id: Int) async throws(AppError) -> CharacterDetail {
        let character = try await repository.character(id: id)

        // Es raro, pero un personaje puede no tener episodios. Si no cortamos aquí
        // hacemos un viaje al servidor para nada, y encima mal formado: el endpoint
        // de lote no tiene forma válida con una lista de ids vacía.
        guard !character.episodeIDs.isEmpty else {
            return CharacterDetail(character: character, episodes: [])
        }

        // TODO: [Fuera de alcance · README §6] Si solo falla la petición de episodios,
        // enseñar el personaje con un aviso de "episodios no disponibles" en vez de
        // tirar la pantalla entera. Hacerlo bien pide un tipo de resultado parcial,
        // que es más de lo que necesita el MVP.
        let episodes = try await repository.episodes(ids: character.episodeIDs)
        return CharacterDetail(character: character, episodes: episodes)
    }
}
