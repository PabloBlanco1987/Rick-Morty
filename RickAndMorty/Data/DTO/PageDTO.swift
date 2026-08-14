import Foundation

/// The API's pagination envelope, generic over whatever it wraps.
struct PageDTO<Item: Decodable & Sendable>: Decodable, Sendable {
    struct Info: Decodable, Sendable {
        let count: Int
        let pages: Int
        let next: String?
        let prev: String?
    }

    let info: Info
    let results: [Item]
}
