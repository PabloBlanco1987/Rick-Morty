import Foundation
@testable import RickAndMorty

/// A `CharacterRepository` with scripted results, for testing use cases in isolation
/// from anything that resembles a network.
actor StubCharacterRepository: CharacterRepository {
    private let charactersResult: Result<Page<Character>, AppError>
    private let characterResult: Result<Character, AppError>
    private let episodesResult: Result<[Episode], AppError>

    private(set) var requestedEpisodeIDs: [[Int]] = []
    private(set) var requestedPages: [Int] = []

    var episodesCallCount: Int { requestedEpisodeIDs.count }

    init(
        characters: Result<Page<Character>, AppError> = .success(.empty()),
        character: Result<Character, AppError> = .success(.stub()),
        episodes: Result<[Episode], AppError> = .success([])
    ) {
        self.charactersResult = characters
        self.characterResult = character
        self.episodesResult = episodes
    }

    func characters(page: Int, filter: CharacterFilter) async throws(AppError) -> Page<Character> {
        requestedPages.append(page)
        return try charactersResult.get()
    }

    func character(id: Int) async throws(AppError) -> Character {
        try characterResult.get()
    }

    func episodes(ids: [Int]) async throws(AppError) -> [Episode] {
        requestedEpisodeIDs.append(ids)
        return try episodesResult.get()
    }
}

extension Character {
    /// A valid character, with only the fields a given test cares about overridden.
    static func stub(
        id: Int = 1,
        name: String = "Rick Sanchez",
        status: Status = .alive,
        episodeIDs: [Int] = [1, 2]
    ) -> Character {
        Character(
            id: id,
            name: name,
            status: status,
            species: "Human",
            type: nil,
            gender: .male,
            origin: "Earth (C-137)",
            location: "Citadel of Ricks",
            imageURL: URL(string: "https://rickandmortyapi.com/api/character/avatar/1.jpeg"),
            episodeIDs: episodeIDs
        )
    }
}
