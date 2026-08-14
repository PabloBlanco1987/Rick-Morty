import Foundation

/// A character of the show, as the rest of the app understands it.
///
/// Deliberately free of transport concerns: no strings standing in for URLs, no
/// empty strings standing in for "absent", no unbounded raw values. `CharacterDTO`
/// and `CharacterMapper` absorb the API's messiness at the boundary so that no
/// other layer has to defend against it.
struct Character: Identifiable, Hashable, Sendable {
    let id: Int
    let name: String
    let status: Status
    let species: String
    /// Sub-species or variant. The API sends `""` when there is none; the domain says `nil`.
    let type: String?
    let gender: Gender
    let origin: String
    let location: String
    /// `nil` when the API hands us something that is not a usable URL. The UI has a
    /// placeholder either way, so a broken link degrades instead of dropping the character.
    let imageURL: URL?
    let episodeIDs: [Int]
}

extension Character {
    /// Closed set on purpose: an unrecognised value from the API becomes `.unknown`
    /// rather than failing the whole page.
    enum Status: String, Hashable, Sendable, CaseIterable {
        case alive, dead, unknown
    }

    enum Gender: String, Hashable, Sendable, CaseIterable {
        case female, male, genderless, unknown
    }
}
