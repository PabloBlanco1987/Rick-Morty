import Foundation

/// The character payload exactly as the API sends it.
///
/// Only the fields the app consumes are declared — `url` and `created` are ignored
/// rather than carried around unused. Keeping the DTO separate from `Character` is
/// what lets the API add, rename or loosen a field without the change rippling past
/// `CharacterMapper`.
struct CharacterDTO: Decodable, Sendable, Equatable {
    let id: Int
    let name: String
    let status: String
    let species: String
    let type: String
    let gender: String
    let origin: PlaceDTO
    let location: PlaceDTO
    let image: String
    let episode: [String]
}

struct PlaceDTO: Decodable, Sendable, Equatable {
    let name: String
    let url: String
}
