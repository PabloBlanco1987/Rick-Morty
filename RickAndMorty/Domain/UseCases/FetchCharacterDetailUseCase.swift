import Foundation

/// Assembles the detail screen's data: the character plus the episodes it appears in.
///
/// This is where a use case earns its place over a straight repository call — the
/// two-request orchestration lives here instead of leaking into the view model.
struct FetchCharacterDetailUseCase: Sendable {
    private let repository: any CharacterRepository

    init(repository: any CharacterRepository) {
        self.repository = repository
    }

    func execute(id: Int) async throws(AppError) -> CharacterDetail {
        let character = try await repository.character(id: id)

        // A character with no episodes is rare but legal. Skipping the second request
        // keeps it from becoming a pointless round trip — and a malformed one, since
        // the batch endpoint has no meaningful form for an empty id list.
        guard !character.episodeIDs.isEmpty else {
            return CharacterDetail(character: character, episodes: [])
        }

        // TODO: [Out of scope · README §6] Degrade gracefully when only the episode
        // request fails, showing the character with an inline "episodes unavailable"
        // notice instead of failing the whole screen. Doing it properly means a
        // partial-success result type, which is more surface than the MVP warrants.
        let episodes = try await repository.episodes(ids: character.episodeIDs)
        return CharacterDetail(character: character, episodes: episodes)
    }
}
