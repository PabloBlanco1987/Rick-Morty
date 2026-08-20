import Foundation

/// Converts what the API sends into domain entities. Mapping never fails: an unknown
/// status becomes .unknown, a non-URL image becomes nil, an empty type becomes nil —
/// one odd record can't cost the user the whole page of results.
enum CharacterMapper {
    static func map(_ dto: CharacterDTO) -> Character {
        Character(
            id: dto.id,
            name: dto.name,
            status: Character.Status(rawValue: dto.status.lowercased()) ?? .unknown,
            species: dto.species,
            type: dto.type.isEmpty ? nil : dto.type,
            gender: Character.Gender(rawValue: dto.gender.lowercased()) ?? .unknown,
            origin: placeName(dto.origin.name),
            location: placeName(dto.location.name),
            imageURL: imageURL(from: dto.image),
            episodeIDs: episodeIDs(from: dto.episode)
        )
    }

    static func map(_ dto: PageDTO<CharacterDTO>, page: Int) -> Page<Character> {
        Page(
            items: dto.results.map(map),
            currentPage: page,
            totalPages: dto.info.pages
        )
    }

    // "unknown" is the API's sentinel for an unknown place. In the domain, absence is
    // nil — not a string every screen would have to recognize and translate itself.
    private static func placeName(_ raw: String) -> String? {
        raw == "unknown" ? nil : raw
    }

    // TODO: [Out of scope · README §8] Places as somewhere to go, not text to read.
    /*
     Reason: `PlaceDTO` decodes `name` and drops the `url` sitting right next to it, so
     origin and location reach the domain as strings. That's everything the detail can
     do with them today — there's no location screen to open.
     Ready to plug in: `PlaceDTO` gains `url`, this file reads its id with the same
     last-path-component rule `episodeIDs` already uses, and `Character`'s two `String?`
     become a `Place` carrying name and id. The id is the whole point: it's what a row
     would navigate by, and it costs one decoded field.
     */

    private static func imageURL(from raw: String) -> URL? {
        guard let url = URL(string: raw), url.scheme != nil, url.host() != nil else { return nil }
        return url
    }

    // The API returns episode links, the domain wants ids. Anything that doesn't end
    // in an integer is dropped, rather than default to a wrong id.
    private static func episodeIDs(from urls: [String]) -> [Int] {
        urls.compactMap { Int(URL(string: $0)?.lastPathComponent ?? "") }
    }
}
