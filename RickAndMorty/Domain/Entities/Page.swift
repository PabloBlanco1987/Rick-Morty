import Foundation

/// A page of a paginated collection, addressed by page number rather than the API's
/// `info.next` URL — a domain type shouldn't carry transport, or need a fake host to
/// construct in a test.
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
