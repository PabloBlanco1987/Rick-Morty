import Foundation

/// Fetches one page of characters, optionally narrowed by a filter.
///
/// There is no separate `SearchCharactersUseCase`: searching *is* listing with a
/// filter applied, and the pagination rules are identical. Splitting them would
/// duplicate that logic for the sake of a name.
struct FetchCharactersUseCase: Sendable {
    private let repository: any CharacterRepository

    init(repository: any CharacterRepository) {
        self.repository = repository
    }

    func execute(page: Int = 1, filter: CharacterFilter = .none) async throws(AppError) -> Page<Character> {
        try await repository.characters(page: page, filter: filter)
    }
}
