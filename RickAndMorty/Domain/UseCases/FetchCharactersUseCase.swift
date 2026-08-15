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

    func execute(page: Int = 1, filter: CharacterFilter = .empty) async throws(AppError) -> Page<Character> {
        try await repository.characters(page: page, filter: filter)
    }
}
