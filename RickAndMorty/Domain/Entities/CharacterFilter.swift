import Foundation

/// The criteria a character listing can be narrowed by.
///
/// Search and filtering are the same operation as far as the domain is concerned:
/// both narrow the same listing, so they share one type and one use case instead of
/// duplicating the pagination logic twice.
struct CharacterFilter: Hashable, Sendable {
    var name: String = ""
    var status: Character.Status?
    var gender: Character.Gender?
    var species: String = ""

    static let none = CharacterFilter()

    /// Whitespace-only input is not a search term.
    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedSpecies: String {
        species.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isEmpty: Bool {
        trimmedName.isEmpty && status == nil && gender == nil && trimmedSpecies.isEmpty
    }
}
