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

        // Si esto falla, falla la operación entera: el caso de uso devuelve el detalle
        // completo o no devuelve nada. Que el usuario acabe viendo igualmente el
        // personaje cuando venía de la lista lo resuelve CharacterDetailViewModel, que
        // conserva lo que ya tenía y enseña el error solo en la sección de episodios.
        //
        // Lo que queda sin cubrir es entrar directamente al detalle —un enlace profundo,
        // una notificación— y que fallen solo los episodios: ahí no hay nada que
        // conservar y se pierde también el personaje, que sí había llegado. Arreglarlo
        // bien pide devolver un resultado parcial (el personaje más el estado de sus
        // episodios) y es más tipo del que necesita esta pantalla hoy. Ver README,
        // "Límites conocidos".
        let episodes = try await repository.episodes(ids: character.episodeIDs)
        return CharacterDetail(character: character, episodes: episodes)
    }
}
