import Foundation

// Raíz de composición: el único sitio donde se nombran los tipos concretos del grafo de
// datos. Todo lo que hay debajo depende de protocolos, que es lo que lo hace
// intercambiable. Un test de UI arranca la misma app con un repositorio de mentira y
// nadie por debajo nota la diferencia.
//
// La caché de imágenes es la excepción, y a propósito: entra por el entorno de SwiftUI
// (ver CachedAsyncImage) porque qué tamaño necesita una imagen lo decide la vista.
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

    // El que se monta al arrancar. Normalmente es el de producción; cuando lo lanza un
    // test de UI, el mismo grafo con datos en memoria. Es el único sitio donde eso se
    // decide, y por debajo de aquí no hay una sola línea que cambie.
    static func forLaunch() -> AppDependencies {
        #if DEBUG
        if LaunchEnvironment.isStubbed {
            return AppDependencies(repository: StubbedCharacterRepository())
        }
        #endif
        return .live()
    }
}
