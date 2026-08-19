import Foundation

/// Domain model for a character, decoupled from the API's DTO shape.
struct Character: Identifiable, Hashable, Sendable {
    let id: Int
    let name: String
    let status: Status
    let species: String
    let type: String?
    let gender: Gender
    let origin: String?
    let location: String?
    let imageURL: URL?
    let episodeIDs: [Int]
}

extension Character {
    enum Status: String, Hashable, Sendable, CaseIterable {
        case alive, dead, unknown
    }

    enum Gender: String, Hashable, Sendable, CaseIterable {
        case female, male, genderless, unknown
    }
}
