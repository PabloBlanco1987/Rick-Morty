import Foundation

/// The API's pagination envelope, generic over what's inside. `info` only declares
/// `pages` — count, next, and prev arrive in the JSON but nothing reads them, since
/// paging goes by number, not by following next.
struct PageDTO<Item: Decodable & Sendable>: Decodable, Sendable {
    struct Info: Decodable, Sendable {
        let pages: Int
    }

    let info: Info
    let results: [Item]
}
