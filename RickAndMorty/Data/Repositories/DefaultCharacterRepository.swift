import Foundation

/// Fulfils the domain's `CharacterRepository` contract against the live API.
struct DefaultCharacterRepository: CharacterRepository {
    private let remote: CharacterRemoteDataSource

    init(remote: CharacterRemoteDataSource) {
        self.remote = remote
    }

    func characters(page: Int, filter: CharacterFilter) async throws(AppError) -> Page<Character> {
        do {
            let dto = try await remote.characters(page: page, filter: filter)
            return CharacterMapper.map(dto, page: page)
        } catch {
            // The API answers a filter that matches nothing with 404 and an error body,
            // not with an empty `results` array. "No results" is an outcome of a search,
            // not a failure of it, so it is translated here — at the layer that knows
            // this particular API's habits — and the UI gets an empty state instead of
            // a red error screen.
            if error == .notFound { return .empty(page: page) }
            throw error
        }
    }

    func character(id: Int) async throws(AppError) -> Character {
        // No 404 translation here on purpose: asking for a character that does not
        // exist is a genuine not-found, and the detail screen should say so.
        CharacterMapper.map(try await remote.character(id: id))
    }

    func episodes(ids: [Int]) async throws(AppError) -> [Episode] {
        try await remote.episodes(ids: ids).map(EpisodeMapper.map)
    }
}
