import Foundation

// Una página de una colección paginada.
// Pagino por número de página y no arrastrando el info.next de la API: meter una URL
// en el dominio significa colar el transporte en todas las capas de arriba, y encima
// no puedes construir el tipo en un test sin inventarte un host.
struct Page<Item: Hashable & Sendable>: Hashable, Sendable {
    let items: [Item]
    let currentPage: Int
    let totalPages: Int

    var hasNextPage: Bool { currentPage < totalPages }
    var nextPage: Int? { hasNextPage ? currentPage + 1 : nil }

    static func empty(page: Int = 1) -> Page {
        Page(items: [], currentPage: page, totalPages: 0)
    }
}
