import Foundation

// El sobre de paginación de la API, genérico sobre lo que venga dentro.
// De info solo se declara pages: count, next y prev vienen en el JSON pero nadie los lee
// —se pagina por número, no siguiendo next—, y lo que no se lee no se declara.
struct PageDTO<Item: Decodable & Sendable>: Decodable, Sendable {
    struct Info: Decodable, Sendable {
        let pages: Int
    }

    let info: Info
    let results: [Item]
}
