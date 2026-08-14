import Foundation

/// The domain's view of where characters come from.
///
/// The protocol lives here, next to its consumers, and the Data layer implements it.
/// That is the dependency inversion the whole architecture rests on: `Domain` compiles
/// with no knowledge that HTTP exists, and swapping the source (cache, fixtures,
/// a future local store) touches nothing above this file.
///
/// The typed `throws(AppError)` is deliberate — callers get an exhaustive `switch`
/// over the failure modes instead of an opaque `any Error`.
protocol CharacterRepository: Sendable {
    func characters(page: Int, filter: CharacterFilter) async throws(AppError) -> Page<Character>
    func character(id: Int) async throws(AppError) -> Character
    func episodes(ids: [Int]) async throws(AppError) -> [Episode]
}
