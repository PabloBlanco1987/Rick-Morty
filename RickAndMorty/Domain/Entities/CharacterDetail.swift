import Foundation

/// Everything the detail screen needs, assembled by `FetchCharacterDetailUseCase`
/// so the view model never has to orchestrate two requests itself.
struct CharacterDetail: Hashable, Sendable {
    let character: Character
    let episodes: [Episode]
}
