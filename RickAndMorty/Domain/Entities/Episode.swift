import Foundation

/// An episode a character appears in.
struct Episode: Identifiable, Hashable, Sendable {
    let id: Int
    let name: String
    /// Season/episode code as the show numbers it, e.g. `S01E01`.
    let code: String
    /// `nil` when the API's air date cannot be parsed. Presentation formats this for
    /// the current locale; the domain never stores a pre-formatted string.
    let airDate: Date?
}
