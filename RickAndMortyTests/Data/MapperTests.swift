import Foundation
import Testing
@testable import RickAndMorty

@Suite("Character mapper")
struct CharacterMapperTests {
    private func decode(_ json: String) throws -> CharacterDTO {
        try JSONDecoder.rickAndMorty.decode(CharacterDTO.self, from: Data(json.utf8))
    }

    @Test("Maps a well-formed payload field by field")
    func mapsEveryField() throws {
        let character = CharacterMapper.map(try decode(JSONFixtures.rick))

        #expect(character.id == 1)
        #expect(character.name == "Rick Sanchez")
        #expect(character.status == .alive)
        #expect(character.species == "Human")
        #expect(character.gender == .male)
        #expect(character.origin == "Earth (C-137)")
        #expect(character.location == "Citadel of Ricks")
        #expect(character.imageURL?.lastPathComponent == "1.jpeg")
        #expect(character.episodeIDs == [1, 2])
    }

    @Test("An absent sub-species is nil, not an empty string")
    func emptyTypeBecomesNil() throws {
        #expect(CharacterMapper.map(try decode(JSONFixtures.rick)).type == nil)
    }

    @Test("A status the app does not know degrades to unknown instead of failing")
    func unknownStatusDegrades() throws {
        let character = CharacterMapper.map(try decode(JSONFixtures.malformedCharacter))
        #expect(character.status == .unknown)
        #expect(character.gender == .unknown)
    }

    @Test("An unusable image URL becomes nil so the placeholder takes over")
    func invalidImageBecomesNil() throws {
        #expect(CharacterMapper.map(try decode(JSONFixtures.malformedCharacter)).imageURL == nil)
    }

    @Test("Episode links that do not end in an id are dropped, never defaulted")
    func dropsUnparseableEpisodeLinks() throws {
        #expect(CharacterMapper.map(try decode(JSONFixtures.malformedCharacter)).episodeIDs == [7])
    }

    @Test("A page carries its own number plus the API's totals")
    func mapsWholePage() throws {
        let dto = try JSONDecoder.rickAndMorty.decode(
            PageDTO<CharacterDTO>.self,
            from: Data(JSONFixtures.charactersPage.utf8)
        )
        let page = CharacterMapper.map(dto, page: 1)

        #expect(page.items.count == 2)
        #expect(page.currentPage == 1)
        #expect(page.totalPages == 42)
        #expect(page.hasNextPage)
    }
}

@Suite("Episode mapper")
struct EpisodeMapperTests {
    private func decode(_ json: String) throws -> EpisodeDTO {
        try JSONDecoder.rickAndMorty.decode(EpisodeDTO.self, from: Data(json.utf8))
    }

    @Test("Parses the API's US-English air date regardless of device locale")
    func parsesAirDate() throws {
        let episode = EpisodeMapper.map(try decode(JSONFixtures.singleEpisode))
        let airDate = try #require(episode.airDate)
        let components = Calendar(identifier: .gregorian).dateComponents(in: .gmt, from: airDate)

        #expect(episode.id == 1)
        #expect(episode.name == "Pilot")
        #expect(episode.code == "S01E01")
        #expect(components.year == 2013)
        #expect(components.month == 12)
        #expect(components.day == 2)
    }

    @Test("An unparseable air date is nil, not a wrong date")
    func unparseableAirDateIsNil() throws {
        #expect(EpisodeMapper.map(try decode(JSONFixtures.malformedEpisode)).airDate == nil)
    }

    @Test("snake_case keys are decoded without hand-written CodingKeys")
    func decodesSnakeCase() throws {
        #expect(try decode(JSONFixtures.singleEpisode).airDate == "December 2, 2013")
    }
}
