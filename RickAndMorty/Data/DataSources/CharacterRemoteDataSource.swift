import Foundation

/// Knows which endpoints exist and what shape each one answers with. Nothing more:
/// no domain types cross this boundary, no caching decisions are taken here.
///
/// It exists as its own type so that adding offline support later means adding a
/// sibling `LocalCharacterDataSource` and a policy in the repository, rather than
/// unpicking network code from mapping code.
struct CharacterRemoteDataSource: Sendable {
    private let client: any HTTPClient

    init(client: any HTTPClient) {
        self.client = client
    }

    func characters(page: Int, filter: CharacterFilter) async throws(AppError) -> PageDTO<CharacterDTO> {
        try await client.send(RickAndMortyAPI.characters(page: page, filter: filter))
    }

    func character(id: Int) async throws(AppError) -> CharacterDTO {
        try await client.send(RickAndMortyAPI.character(id: id))
    }

    /// Absorbs the batch endpoint's shape change: `/episode/1,2` answers with an
    /// array, `/episode/1` with a bare object. Callers always get an array.
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
