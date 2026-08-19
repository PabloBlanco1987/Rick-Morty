import Foundation
import Testing
@testable import RickAndMorty

// DTOs are decoded with the same decoder the app uses, so what reaches the mapper is
// exactly what would reach it in production. The type is inferred by the caller.
private func decode<DTO: Decodable>(_ json: String) throws -> DTO {
    try JSONDecoder.rickAndMorty.decode(DTO.self, from: Data(json.utf8))
}

@Suite("Character mapper")
struct CharacterMapperTests {
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

    @Test("An absent sub-species is nil, not an empty string; a present one comes through")
    func emptyTypeBecomesNil() throws {
        #expect(CharacterMapper.map(try decode(JSONFixtures.rick)).type == nil)
        #expect(CharacterMapper.map(try decode(JSONFixtures.malformedCharacter)).type == "Superposition")
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

    @Test(
        "Only an absolute URL with a host counts as an image",
        arguments: ["not a url", "/api/character/avatar/1.jpeg", "rickandmortyapi.com/avatar/1.jpeg", "https://"]
    )
    func relativeOrSchemelessImageBecomesNil(raw: String) throws {
        // Since iOS 17, URL(string:) accepts almost any text: "not a url" parses as a
        // relative reference and only "" returns nil. Without the scheme-and-host
        // check, these four would reach the download as URLs and fail there, instead of
        // falling back to the placeholder up front.
        let rick: CharacterDTO = try decode(JSONFixtures.rick)
        let dto = CharacterDTO(
            id: rick.id,
            name: rick.name,
            status: rick.status,
            species: rick.species,
            type: rick.type,
            gender: rick.gender,
            origin: rick.origin,
            location: rick.location,
            image: raw,
            episode: rick.episode
        )

        #expect(CharacterMapper.map(dto).imageURL == nil)
    }

    @Test("The API's 'unknown' place is an absence, not a word to show")
    func unknownPlaceBecomesNil() throws {
        // The API sends the literal "unknown" when it doesn't know the origin or
        // location. In the domain that's nil, so the screen — not every place that
        // renders it — decides how to say it, and in what language.
        let glitch = CharacterMapper.map(try decode(JSONFixtures.malformedCharacter))
        let rick = CharacterMapper.map(try decode(JSONFixtures.rick))

        #expect(glitch.origin == nil)
        #expect(glitch.location == nil)
        #expect(rick.origin == "Earth (C-137)")
    }

    @Test("Episode links that do not end in an id are dropped, never defaulted")
    func dropsUnparseableEpisodeLinks() throws {
        #expect(CharacterMapper.map(try decode(JSONFixtures.malformedCharacter)).episodeIDs == [7])
    }

    @Test("A page carries the number it was asked for plus the API's totals")
    func mapsWholePage() throws {
        // The API doesn't say which page it is — only how many there are — so the
        // number comes from whoever asked for it. Page 3, not 1, so a hardcoded literal
        // can't pass by accident.
        let page = CharacterMapper.map(try decode(JSONFixtures.charactersPage), page: 3)

        #expect(page.items.count == 2)
        #expect(page.currentPage == 3)
        #expect(page.totalPages == 42)
        #expect(page.hasNextPage)
    }
}

@Suite("Episode mapper")
struct EpisodeMapperTests {
    @Test("Parses the API's US-English air date regardless of device locale, as midnight GMT")
    func parsesAirDate() throws {
        // Midnight in GMT, not the device's time zone: it's a calendar day, not an
        // instant, so formatting it in GMT shows the same day anywhere in the world
        let episode = EpisodeMapper.map(try decode(JSONFixtures.singleEpisode))
        let airDate = try #require(episode.airDate)
        let components = Calendar(identifier: .gregorian).dateComponents(in: .gmt, from: airDate)

        #expect(episode.id == 1)
        #expect(episode.name == "Pilot")
        #expect(episode.code == Episode.Code(season: 1, number: 1))
        #expect(components.year == 2013)
        #expect(components.month == 12)
        #expect(components.day == 2)
        #expect(components.hour == 0)
        #expect(components.minute == 0)
    }

    @Test("An unparseable air date is nil, not a wrong date")
    func unparseableAirDateIsNil() throws {
        #expect(EpisodeMapper.map(try decode(JSONFixtures.malformedEpisode)).airDate == nil)
    }

    @Test("snake_case keys are decoded without hand-written CodingKeys")
    func decodesSnakeCase() throws {
        let dto: EpisodeDTO = try decode(JSONFixtures.singleEpisode)
        #expect(dto.airDate == "December 2, 2013")
    }
}
