import Foundation
import Observation

// El estado y las acciones de la pantalla de detalle.
//
// La diferencia con el listado está en de dónde se llega: a esta pantalla se entra
// desde una celda que ya tenía el personaje entero, así que hacer esperar al usuario a
// que vuelva el servidor para enseñarle un nombre que ya estaba en la pantalla anterior
// sería una espera inventada. Por eso el personaje que venía de la lista se guarda
// aparte y la cabecera se pinta en el primer frame; lo que de verdad hay que ir a
// buscar son los episodios.
//
// Aun así se pide el detalle completo por id y no solo los episodios: es lo que hace
// que la pantalla siga funcionando si mañana se llega a ella por un enlace profundo o
// una notificación, sin nadie que le pase el personaje por delante.
@MainActor
@Observable
final class CharacterDetailViewModel {
    private(set) var state: ViewState<CharacterDetail> = .idle

    // Lo que ya se sabía al navegar. Es opcional porque el view model no da por hecho
    // que siempre se llegue desde la lista.
    let knownCharacter: Character?

    private let characterID: Int
    private let fetchCharacterDetail: FetchCharacterDetailUseCase

    init(
        characterID: Int,
        known knownCharacter: Character? = nil,
        fetchCharacterDetail: FetchCharacterDetailUseCase
    ) {
        self.characterID = characterID
        self.knownCharacter = knownCharacter
        self.fetchCharacterDetail = fetchCharacterDetail
    }

    // Lo que pinta la cabecera. Lo cargado manda sobre lo que traíamos: si el servidor
    // dice que el personaje ha cambiado de ubicación desde que se cargó la lista, lo que
    // vale es lo nuevo.
    var character: Character? {
        state.value?.character ?? knownCharacter
    }

    // Los episodios solo existen cuando ha llegado el detalle. Se separa de `state`
    // porque la vista los trata como una sección propia: mientras cargan, la cabecera
    // ya está puesta.
    var episodes: [Episode] {
        state.value?.episodes ?? []
    }

    // Un fallo con el personaje ya en pantalla no es lo mismo que un fallo en blanco.
    // En el primer caso lo que se cae es una sección; en el segundo, la pantalla entera.
    var hasContentOnScreen: Bool {
        character != nil
    }

    // La llama el .task de la vista, y solo carga la primera vez. Aquí no es por volver
    // de otra pantalla —el detalle es la cima de la pila y se destruye al hacer pop—,
    // sino para que la regla sea la misma que en el listado y aguante lo que venga: un
    // enlace profundo, una hoja encima, un split view en iPad, cualquier cosa que haga
    // reaparecer la vista sin recrearla no puede costar otra petición.
    func onAppear() async {
        guard case .idle = state else { return }
        await load()
    }

    func retry() async {
        await load()
    }

    private func load() async {
        state = .loading

        do {
            let detail = try await fetchCharacterDetail.execute(id: characterID)
            // Salir de la pantalla mientras carga no puede dejar un estado escrito a
            // destiempo sobre una vista que ya no está
            guard !Task.isCancelled else { return }
            state = .loaded(detail)
        } catch {
            // Cancelar no es fallar: si el usuario ha vuelto atrás no hay nada que
            // contarle.
            guard error != .cancelled else { return }
            state = .failed(error)
        }
    }
}
