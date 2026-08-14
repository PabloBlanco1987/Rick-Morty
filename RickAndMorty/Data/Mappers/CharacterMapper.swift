import Foundation

/// Turns API payloads into domain entities.
///
/// Mapping is total: no input makes it fail. An unrecognised status becomes
/// `.unknown`, an unparseable image URL becomes `nil`, an empty `type` becomes `nil`.
/// A single odd record must never cost the user a whole page of results.
enum CharacterMapper {
    static func map(_ dto: CharacterDTO) -> Character {
        Character(
            id: dto.id,
            name: dto.name,
            status: Character.Status(rawValue: dto.status.lowercased()) ?? .unknown,
            species: dto.species,
            type: dto.type.isEmpty ? nil : dto.type,
            gender: Character.Gender(rawValue: dto.gender.lowercased()) ?? .unknown,
            origin: dto.origin.name,
            location: dto.location.name,
            imageURL: URL(string: dto.image),
            episodeIDs: episodeIDs(from: dto.episode)
        )
    }

    static func map(_ dto: PageDTO<CharacterDTO>, page: Int) -> Page<Character> {
        Page(
            items: dto.results.map(map),
            currentPage: page,
            totalPages: dto.info.pages,
            totalCount: dto.info.count
        )
    }

    /// The API hands back episode *links*; the domain wants identifiers. Anything that
    /// does not end in an integer is dropped rather than defaulted to a wrong id.
    private static func episodeIDs(from urls: [String]) -> [Int] {
        urls.compactMap { Int(URL(string: $0)?.lastPathComponent ?? "") }
    }
}
