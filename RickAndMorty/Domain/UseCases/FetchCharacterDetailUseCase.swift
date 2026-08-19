import Foundation

/// Assembles the detail screen's data — character plus episodes — by coordinating
/// both repository calls here instead of in the view model.
struct FetchCharacterDetailUseCase: Sendable {
    private let repository: any CharacterRepository

    init(repository: any CharacterRepository) {
        self.repository = repository
    }

    func execute(id: Int) async throws(AppError) -> CharacterDetail {
        let character = try await repository.character(id: id)

        // No episodes means nothing to request — a domain rule, separate from the API's
        // batch endpoint also rejecting an empty id list (the data source's own concern).
        guard !character.episodeIDs.isEmpty else {
            return CharacterDetail(character: character, episodes: [])
        }

        // TODO: [Out of scope · README §8] Deep-linked detail with failed episodes.
        /*
         Reason: reached directly — a deep link, a notification — a failed episodes
         fetch has nothing to fall back on, so the character is lost too, even though it
         did arrive. Fixing this properly means returning a partial result, which is
         more type than this screen needs today, opened only from the list.
         Ready to plug in: would come in as a `CharacterDetail` carrying the character
         plus the episodes' own state (a `Result<[Episode], AppError>`), without
         touching the repository — the view model already separates the header from the
         episodes section.
         */

        // A failed episodes fetch fails the whole use case. CharacterDetailViewModel is
        // what keeps the character on screen anyway, blaming only the episodes section.
        let episodes = try await repository.episodes(ids: character.episodeIDs)
        return CharacterDetail(character: character, episodes: episodes)
    }
}
