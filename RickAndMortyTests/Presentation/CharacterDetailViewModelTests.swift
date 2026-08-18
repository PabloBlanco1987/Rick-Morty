import Foundation
import Testing
@testable import RickAndMorty

// Lo que se prueba aquí, más que la carga, es la regla de la pantalla: que lo que ya se
// sabía al navegar se enseñe desde el primer momento y que un fallo de los episodios no
// se lleve por delante al personaje.
@MainActor
@Suite("Character detail view model")
struct CharacterDetailViewModelTests {
    private func makeSUT(
        _ repository: StubCharacterRepository,
        known: Character? = nil,
        id: Int = 1
    ) -> CharacterDetailViewModel {
        CharacterDetailViewModel(
            characterID: id,
            known: known,
            fetchCharacterDetail: FetchCharacterDetailUseCase(repository: repository)
        )
    }

    private let episodes = [
        Episode(id: 1, name: "Pilot", code: "S01E01", airDate: nil),
        Episode(id: 2, name: "Lawnmower Dog", code: "S01E02", airDate: nil),
    ]

    // MARK: - Carga

    @Test("Starts idle, with nothing loaded")
    func startsIdle() {
        let sut = makeSUT(StubCharacterRepository())

        #expect(sut.state == .idle)
        #expect(sut.episodes.isEmpty)
    }

    @Test("The character that came from the list is on screen before anything is requested")
    func showsTheKnownCharacterUpFront() async {
        // Es la razón de ser de esta pantalla: al tocar una celda ya se sabe el nombre,
        // así que hacer esperar al usuario a que conteste el servidor para enseñárselo
        // sería una espera inventada.
        let repository = StubCharacterRepository()
        let sut = makeSUT(repository, known: .stub(name: "Rick Sanchez"))

        #expect(sut.character?.name == "Rick Sanchez")
        #expect(sut.hasContentOnScreen)
        #expect(await repository.requestedCharacterIDs.isEmpty)
    }

    @Test("Loading brings the character together with its episodes")
    func loadsCharacterAndEpisodes() async {
        let repository = StubCharacterRepository(
            character: .success(.stub(episodeIDs: [1, 2])),
            episodes: .success(episodes)
        )
        let sut = makeSUT(repository, id: 42)

        await sut.onAppear()

        #expect(sut.character?.name == "Rick Sanchez")
        #expect(sut.episodes.map(\.code) == ["S01E01", "S01E02"])
        #expect(await repository.requestedCharacterIDs == [42])
    }

    @Test("What the server returns wins over what the list had")
    func theLoadedCharacterReplacesTheKnownOne() async {
        // La lista pudo cargarse hace diez minutos: si el personaje ha cambiado de
        // ubicación desde entonces, lo que vale es lo que acaba de llegar.
        let repository = StubCharacterRepository(character: .success(.stub(name: "Rick Sanchez")))
        let sut = makeSUT(repository, known: .stub(name: "Stale name"))

        await sut.onAppear()

        #expect(sut.character?.name == "Rick Sanchez")
    }

    @Test("Appearing again does not reload what is already on screen")
    func appearingAgainDoesNotReload() async {
        let repository = StubCharacterRepository()
        let sut = makeSUT(repository)

        await sut.onAppear()
        await sut.onAppear()

        #expect(await repository.requestedCharacterIDs == [1])
    }

    @Test("A character with no episodes is a loaded detail with an empty list, not a failure")
    func noEpisodesIsLoadedNotFailed() async {
        // Que no se pida nada por ellos lo prueba el caso de uso; lo que importa aquí es
        // que la pantalla lo cuente como un resultado —"no sale en ningún episodio"— y no
        // como un error de la sección
        let character = Character.stub(episodeIDs: [])
        let sut = makeSUT(StubCharacterRepository(character: .success(character)))

        await sut.onAppear()

        #expect(sut.state == .loaded(CharacterDetail(character: character, episodes: [])))
        #expect(sut.episodes.isEmpty)
    }

    @Test("Being cancelled is not failing: nothing is written for it")
    func aCancelledLoadIsNotAFailure() async {
        // Si el usuario ha vuelto atrás mientras cargaba, la petición se cancela y no hay
        // nada que contarle: ni un error en la sección de episodios ni en la pantalla
        let sut = makeSUT(StubCharacterRepository(character: .failure(.cancelled)), known: .stub())

        await sut.onAppear()

        #expect(sut.state == .loading)
        #expect(sut.hasContentOnScreen)
    }

    // MARK: - Fallos

    @Test("A failure keeps the character that was already on screen")
    func failureKeepsTheKnownCharacter() async {
        // Solo se han caído los episodios. Cambiar un personaje que ya está pintado por
        // una pantalla de error sería cambiar información por un mensaje.
        let repository = StubCharacterRepository(episodes: .failure(.offline))
        let sut = makeSUT(repository, known: .stub(name: "Rick Sanchez"))

        await sut.onAppear()

        #expect(sut.state == .failed(.offline))
        #expect(sut.character?.name == "Rick Sanchez")
        #expect(sut.hasContentOnScreen)
    }

    @Test("A failure with nothing on screen takes over the whole view")
    func failureWithoutContentOwnsTheScreen() async {
        // Aquí no hay nada que conservar: se ha entrado sin personaje —un enlace
        // profundo— y la petición ha fallado, así que el error es la pantalla.
        let repository = StubCharacterRepository(character: .failure(.notFound))
        let sut = makeSUT(repository)

        await sut.onAppear()

        #expect(sut.state == .failed(.notFound))
        #expect(!sut.hasContentOnScreen)
    }

    @Test("Retrying asks for the detail again")
    func retryingAsksAgain() async {
        let repository = StubCharacterRepository(character: .failure(.timeout))
        let sut = makeSUT(repository, id: 7)

        await sut.onAppear()
        await sut.retry()

        #expect(await repository.requestedCharacterIDs == [7, 7])
    }

    @Test("A retry that succeeds replaces the error with the detail")
    func retryRecovers() async {
        let repository = StubCharacterRepository(
            character: .success(.stub(episodeIDs: [1, 2])),
            episodes: .failure(.server(statusCode: 503))
        )
        let sut = makeSUT(repository)
        await sut.onAppear()
        #expect(sut.state == .failed(.server(statusCode: 503)))

        await repository.setEpisodes(.success(episodes))
        await sut.retry()

        #expect(sut.episodes.count == 2)
    }
}
