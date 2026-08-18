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

        // Es raro, pero un personaje puede no tener episodios, y sin episodios no hay
        // nada que pedir: esta es la regla del dominio, y vale para cualquier
        // repositorio. Que el endpoint de lote de la API no tenga además forma válida
        // sin ids es una manía del transporte, y de esa se protege el data source por
        // su cuenta; aquí se corta por lo primero, no por lo segundo.
        guard !character.episodeIDs.isEmpty else {
            return CharacterDetail(character: character, episodes: [])
        }

        // Si esto falla, falla la operación entera: el caso de uso devuelve el detalle
        // completo o no devuelve nada. Que el usuario acabe viendo igualmente el
        // personaje cuando venía de la lista lo resuelve CharacterDetailViewModel, que
        // conserva lo que ya tenía y enseña el error solo en la sección de episodios.
        //
        // TODO: [Fuera de alcance · README §8] Detalle por enlace profundo con episodios
        // caídos.
        // Motivo: entrando directamente al detalle —un enlace profundo, una notificación—
        // y fallando solo los episodios, no hay nada que conservar y se pierde también el
        // personaje, que sí había llegado. Arreglarlo bien pide devolver un resultado
        // parcial, y es más tipo del que necesita esta pantalla hoy, que solo se abre
        // desde la lista.
        // Preparado: entraría como un `CharacterDetail` que llevara el personaje más el
        // estado de sus episodios (un `Result<[Episode], AppError>`), sin tocar el
        // repositorio: el view model ya separa la cabecera de la sección de episodios.
        let episodes = try await repository.episodes(ids: character.episodeIDs)
        return CharacterDetail(character: character, episodes: episodes)
    }
}
