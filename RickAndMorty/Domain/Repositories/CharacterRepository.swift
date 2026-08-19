import Foundation

/// Where characters come from, as seen from the domain. The protocol lives here, next
/// to who uses it, and Data implements it — the dependency inversion Domain compiles
/// on without knowing HTTP exists.
protocol CharacterRepository: Sendable {
    func characters(page: Int, filter: CharacterFilter, freshness: Freshness) async throws(AppError) -> Page<Character>
    func character(id: Int) async throws(AppError) -> Character
    func episodes(ids: [Int]) async throws(AppError) -> [Episode]
}

/// How fresh a page has to be. Exists for pull-to-refresh: the domain doesn't know
/// what an HTTP cache is, but it knows that gesture means "fetch it again," not "give
/// me whatever you have" — without saying so, Data can't tell those two apart.
enum Freshness: Sendable {
    // Whatever's cached is fine, as long as it's still valid. The default case: a page
    // already seen, a repeated search, coming back from the detail screen.
    case acceptCached
    // Ask the source even if what's cached is still valid.
    case fresh
}
