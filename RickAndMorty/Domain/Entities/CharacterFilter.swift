import Foundation

/// Criteria the character list can be narrowed by.
struct CharacterFilter: Hashable, Sendable {
    var name: String = ""
    var status: Character.Status?
    var gender: Character.Gender?
    var species: String = ""

    static let empty = CharacterFilter()

    // Whitespace-only input doesn't count as a search.
    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedSpecies: String {
        species.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isEmpty: Bool {
        trimmedName.isEmpty && status == nil && gender == nil && trimmedSpecies.isEmpty
    }

    // Same filter with text already trimmed, so "should reload?" and "is this response
    // stale?" compare on the same criteria — a trailing space shouldn't count as a
    // different search.
    var normalized: CharacterFilter {
        var copy = self
        copy.name = trimmedName
        copy.species = trimmedSpecies
        return copy
    }
}
