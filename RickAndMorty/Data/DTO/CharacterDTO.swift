import Foundation

/// The character exactly as the API sends it. Only the fields actually used are
/// declared — url, created, and the origin/location urls are ignored, not carried
/// along. Keeping the DTO separate from Character is what lets the API add, rename, or
/// loosen a field without the change reaching past CharacterMapper.
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
}
