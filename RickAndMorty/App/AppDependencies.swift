import Foundation

// Raíz de composición: el único sitio de la app donde se ven los tipos concretos.
// Todo lo demás depende de protocolos, que es lo que hace el grafo intercambiable.
// Un test de UI arranca la misma app con un repositorio de mentira y nadie por
// debajo nota la diferencia.
struct AppDependencies: Sendable {
    let fetchCharacters: FetchCharactersUseCase
    let fetchCharacterDetail: FetchCharacterDetailUseCase

    init(repository: any CharacterRepository) {
        self.fetchCharacters = FetchCharactersUseCase(repository: repository)
        self.fetchCharacterDetail = FetchCharacterDetailUseCase(repository: repository)
    }

    // El grafo con el que va la app en producción:
    // cliente con reintentos -> data source remoto -> repositorio -> casos de uso
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
