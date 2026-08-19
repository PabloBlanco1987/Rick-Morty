import Foundation

/// What the detail screen needs, already assembled by FetchCharacterDetailUseCase.
struct CharacterDetail: Hashable, Sendable {
    let character: Character
    let episodes: [Episode]
}
