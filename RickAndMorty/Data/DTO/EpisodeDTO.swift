import Foundation

/// An episode exactly as the API sends it.
struct EpisodeDTO: Decodable, Sendable, Equatable {
    let id: Int
    let name: String
    let airDate: String
    let episode: String
}
