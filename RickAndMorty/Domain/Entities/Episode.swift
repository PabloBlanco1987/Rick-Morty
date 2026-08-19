import Foundation

/// An episode a character appears in.
struct Episode: Identifiable, Hashable, Sendable {
    let id: Int
    let name: String
    let code: String
    let airDate: Date?
}
