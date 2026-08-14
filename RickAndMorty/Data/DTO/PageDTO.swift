import Foundation

// El sobre de paginación de la API, genérico sobre lo que venga dentro
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
