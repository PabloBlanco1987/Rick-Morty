import Foundation

/// Fulfills the domain's CharacterRepository contract against the real API.
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
            // A filter with no matches gets a 404 with an error body, not an empty
            // results array. No results is a valid outcome, not a failure, so it's
            // translated here — the UI shows an empty state, not an error screen.
            if error == .notFound { return .empty(page: page) }
            throw error
        }
    }

    func character(id: Int) async throws(AppError) -> Character {
        CharacterMapper.map(try await remote.character(id: id))
    }

    func episodes(ids: [Int]) async throws(AppError) -> [Episode] {
        try await remote.episodes(ids: ids).map(EpisodeMapper.map)
    }
}
