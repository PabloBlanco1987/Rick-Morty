import Foundation

/// One page of a paginated collection.
///
/// Pagination is modelled by page *number*, not by carrying the API's `info.next`
/// URL around. A URL in the domain would leak the transport into every layer above
/// it and make the type impossible to build in a test without inventing a host.
struct Page<Item: Hashable & Sendable>: Hashable, Sendable {
    let items: [Item]
    let currentPage: Int
    let totalPages: Int
    let totalCount: Int

    var hasNextPage: Bool { currentPage < totalPages }
    var nextPage: Int? { hasNextPage ? currentPage + 1 : nil }

    static func empty(page: Int = 1) -> Page {
        Page(items: [], currentPage: page, totalPages: 0, totalCount: 0)
    }
}
