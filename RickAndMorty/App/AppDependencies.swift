import Foundation

/// The composition root: the only place in the app where concrete types meet.
///
/// Everything else depends on protocols, which is what makes the graph swappable —
/// a UI test launches the same app with a stubbed repository and nothing downstream
/// can tell the difference.
struct AppDependencies: Sendable {
    let fetchCharacters: FetchCharactersUseCase
    let fetchCharacterDetail: FetchCharacterDetailUseCase

    init(repository: any CharacterRepository) {
        self.fetchCharacters = FetchCharactersUseCase(repository: repository)
        self.fetchCharacterDetail = FetchCharacterDetailUseCase(repository: repository)
    }

    /// The graph the shipping app runs on: retrying client → remote data source →
    /// repository → use cases.
    static func live() -> AppDependencies {
        AppDependencies(
            repository: DefaultCharacterRepository(
                remote: CharacterRemoteDataSource(
                    client: RetryingHTTPClient(wrapping: URLSessionHTTPClient())
                )
            )
        )
    }
}
