import Foundation

/// An episode a character appears in.
struct Episode: Identifiable, Hashable, Sendable {
    let id: Int
    let name: String
    // Where it sits in the series. `nil` when the API's code can't be read, the same rule
    // `airDate` follows: no place at all beats a made-up one.
    let code: Code?
    let airDate: Date?
}

extension Episode {
    /// An episode's place in the series: the API's "S01E08" as the two numbers it means.
    ///
    /// The wire format stops at the mapper on purpose. Holding two numbers is what lets
    /// the screen word them — "Season 1 · Episode 8" — and lets another language word or
    /// order them differently, without anyone pulling a string apart a second time. It's
    /// also what drops the padding zeros: they're a property of the API's notation, not
    /// of the season.
    struct Code: Hashable, Sendable {
        let season: Int
        let number: Int
    }
}
