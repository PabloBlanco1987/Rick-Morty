import Foundation

/// Fetches a page of characters, filter optional. No separate SearchCharactersUseCase:
/// searching is listing with a filter set, same pagination rules — splitting them would
/// just duplicate that logic for another name.
struct FetchCharactersUseCase: Sendable {
    private let repository: any CharacterRepository

    init(repository: any CharacterRepository) {
        self.repository = repository
    }

    // Only pull-to-refresh changes freshness; every other load accepts what's cached,
    // which is why returning from the detail or repeating a search costs no request.
    func execute(
        page: Int,
        filter: CharacterFilter,
        freshness: Freshness = .acceptCached
    ) async throws(AppError) -> Page<Character> {
        try await repository.characters(page: page, filter: filter, freshness: freshness)
    }
}
