import Foundation

struct EpisodeDTO: Decodable, Sendable, Equatable {
    let id: Int
    let name: String
    /// `air_date` in the payload, e.g. `"December 2, 2013"`. Decoded by the
    /// `convertFromSnakeCase` strategy rather than a hand-written `CodingKeys`.
    let airDate: String
    /// The season/episode code, e.g. `"S01E01"`.
    let episode: String
}
