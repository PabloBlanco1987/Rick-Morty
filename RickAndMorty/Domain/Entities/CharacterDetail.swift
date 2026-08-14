import Foundation

// Lo que necesita la pantalla de detalle, ya montado por FetchCharacterDetailUseCase
// para que el view model no tenga que encadenar dos llamadas.
struct CharacterDetail: Hashable, Sendable {
    let character: Character
    let episodes: [Episode]
}
