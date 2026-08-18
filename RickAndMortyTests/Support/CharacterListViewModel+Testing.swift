import Foundation
import Testing
@testable import RickAndMorty

// Lo que comparten las tres suites del listado —carga y paginación, búsqueda y filtros,
// refresco— para montar el view model y moverlo. Escrito una vez para que las tres lo
// hagan igual: antes cada suite tenía su copia, y tres copias es la forma más fácil de
// que dentro de un mes solo una sepa cómo se simula llegar al fondo.
@MainActor
extension CharacterListViewModel {
    // El freno entre páginas y la espera de la búsqueda se registran en vez de dormirse:
    // la suite se queda en milisegundos y además se puede comprobar que existen
    static func forTesting(
        _ repository: StubCharacterRepository,
        recordingWaitsInto recorder: SleepRecorder? = nil
    ) -> CharacterListViewModel {
        CharacterListViewModel(
            fetchCharacters: FetchCharactersUseCase(repository: repository),
            sleep: { await recorder?.record($0) }
        )
    }

    // El view model junto al repositorio con una respuesta por página, que es lo que
    // hace falta para probar la paginación y lo que se conserva cuando algo falla
    static func forTesting(pages: [Int: Result<Page<Character>, AppError>]) -> (
        CharacterListViewModel, StubCharacterRepository
    ) {
        let repository = StubCharacterRepository(charactersByPage: pages)
        return (forTesting(repository), repository)
    }

    // Simula que aparece la última celda cargada, que es lo que hace el grid al llegar
    // al fondo, y espera a que termine lo que eso haya disparado
    func scrollToTheEnd() async throws {
        let last = try #require(state.value?.last)
        loadNextPageIfNeeded(after: last)
        await pagingTask?.value
    }
}
