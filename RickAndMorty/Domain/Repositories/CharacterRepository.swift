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

// TODO: [Out of scope · README §8] Location and Episode as domains of their own.
/*
 Reason: `Episode` exists here as what one screen needs — a name, a code, a date — and a
 location is a name on that same screen. Neither is browsable, so neither has a
 repository, a use case, or a filter of its own, and writing them before there's a
 screen would be designing against a guess.
 Ready to plug in: as siblings of this protocol, not as more methods on it —
 `LocationRepository` and `EpisodeRepository`, each with the same three calls, so every
 view model keeps depending only on what it actually uses. `Page` is generic over its
 item and `Freshness` and `AppError` know nothing about characters, so what a location
 list adds is a `Location` entity, a `LocationFilter`, its mappers, and its use cases —
 not another pagination.
 */
