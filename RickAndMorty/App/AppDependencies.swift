import Foundation

/// Composition root: the only place concrete types of the data graph get named.
/// Everything below depends on protocols, which is what makes it swappable.
struct AppDependencies: Sendable {
    let fetchCharacters: FetchCharactersUseCase
    let fetchCharacterDetail: FetchCharacterDetailUseCase

    init(repository: any CharacterRepository) {
        self.fetchCharacters = FetchCharactersUseCase(repository: repository)
        self.fetchCharacterDetail = FetchCharacterDetailUseCase(repository: repository)
    }

    static func forLaunch() -> AppDependencies {
        #if DEBUG
        if LaunchEnvironment.isStubbed {
            return AppDependencies(
                repository: StubbedCharacterRepository(refreshFails: LaunchEnvironment.refreshFails)
            )
        }
        #endif
        return .live()
    }

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
