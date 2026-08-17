import Foundation

// Trae una página de personajes, con filtro si hace falta.
// No hay un SearchCharactersUseCase aparte: buscar es listar con un filtro puesto y
// las reglas de paginación son las mismas. Separarlos sería duplicar esa lógica
// solo para tener otro nombre.
struct FetchCharactersUseCase: Sendable {
    private let repository: any CharacterRepository

    init(repository: any CharacterRepository) {
        self.repository = repository
    }

    // freshness solo lo cambia el pull to refresh; el resto de cargas se conforman con lo
    // que haya guardado, que es lo que hace que volver del detalle o repetir una búsqueda
    // no cueste una petición
    func execute(
        page: Int = 1,
        filter: CharacterFilter = .empty,
        freshness: Freshness = .acceptCached
    ) async throws(AppError) -> Page<Character> {
        try await repository.characters(page: page, filter: filter, freshness: freshness)
    }
}
