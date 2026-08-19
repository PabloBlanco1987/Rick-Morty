import Foundation

/// Knows which endpoints exist and what shape each answers with — nothing more, no
/// domain type crosses here and no caching gets decided. A separate type so adding
/// offline support later means dropping in a LocalCharacterDataSource and a policy in
/// the repository, not untangling network code from mapping code.
struct CharacterRemoteDataSource: Sendable {
    private let client: any HTTPClient

    init(client: any HTTPClient) {
        self.client = client
    }

    func characters(
        page: Int,
        filter: CharacterFilter,
        freshness: Freshness = .acceptCached
    ) async throws(AppError) -> PageDTO<CharacterDTO> {
        try await client.send(RickAndMortyAPI.characters(page: page, filter: filter, freshness: freshness))
    }

    func character(id: Int) async throws(AppError) -> CharacterDTO {
        try await client.send(RickAndMortyAPI.character(id: id))
    }

    func episodes(ids: [Int]) async throws(AppError) -> [EpisodeDTO] {
        guard !ids.isEmpty else { return [] }

        let endpoint = RickAndMortyAPI.episodes(ids: ids)

        guard ids.count > 1 else {
            let single = try await client.send(endpoint, as: EpisodeDTO.self)
            return [single]
        }

        return try await client.send(endpoint, as: [EpisodeDTO].self)
    }
}
