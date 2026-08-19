import Foundation
@testable import RickAndMorty

/// A `CharacterRepository` with canned results, to test the use cases without
/// anything resembling a network.
actor StubCharacterRepository: CharacterRepository {
    private var charactersByPage: [Int: Result<Page<Character>, AppError>]
    private let charactersFallback: Result<Page<Character>, AppError>
    private let characterResult: Result<Character, AppError>
    private var episodesResult: Result<[Episode], AppError>

    private(set) var requestedEpisodeIDs: [[Int]] = []
    private(set) var requestedPages: [Int] = []
    // The criteria each listing was requested with — distinguishes a search that hits
    // the server from one that just filters what's already on the phone.
    private(set) var requestedFilters: [CharacterFilter] = []
    // And with how much freshness — distinguishes a pull-to-refresh, which must
    // revalidate, from other loads, which settle for what's cached.
    private(set) var requestedFreshness: [Freshness] = []
    private(set) var requestedCharacterIDs: [Int] = []

    // If set, each listing pauses here before answering. Lets a request stay frozen
    // in flight while the test changes the filter, refreshes, or requests another
    // page, then checks what happens with a response that arrives late. Only the
    // listing gates: detail and episodes have no races to test.
    private var gate: AsyncGate?

    var episodesCallCount: Int { requestedEpisodeIDs.count }
    var requestedSearchTerms: [String] { requestedFilters.map(\.trimmedName) }

    init(
        characters: Result<Page<Character>, AppError> = .success(.empty()),
        character: Result<Character, AppError> = .success(.stub()),
        episodes: Result<[Episode], AppError> = .success([])
    ) {
        self.charactersByPage = [:]
        self.charactersFallback = characters
        self.characterResult = character
        self.episodesResult = episodes
    }

    // A distinct response per page, needed to test pagination: accumulating page 2
    // onto page 1, or page 7 failing without pages 1-6 falling with it. Anything
    // missing from the dictionary comes back as an empty page. Listing only: paging
    // doesn't request detail or episodes.
    init(charactersByPage: [Int: Result<Page<Character>, AppError>]) {
        self.charactersByPage = charactersByPage
        self.charactersFallback = .success(.empty())
        self.characterResult = .success(.stub())
        self.episodesResult = .success([])
    }

    // Changes what gets answered from now on, to test what happens when something
    // that was working starts failing — a refresh that fails after the list already
    // loaded, for example.
    func setCharacters(_ result: Result<Page<Character>, AppError>, forPage page: Int) {
        charactersByPage[page] = result
    }

    // Same for episodes, needed to test that a retry recovers: fails first,
    // answers on the second try.
    func setEpisodes(_ result: Result<[Episode], AppError>) {
        episodesResult = result
    }

    // From here on, listings block at the gate until the test opens it; with nil,
    // subsequent calls answer immediately and only the already-blocked ones keep
    // waiting. The request is recorded before pausing, so the test can wait for it
    // with `gate.waitUntilReached()` and know it's frozen inside.
    func holdListings(at gate: AsyncGate?) {
        self.gate = gate
    }

    func characters(
        page: Int,
        filter: CharacterFilter,
        freshness: Freshness
    ) async throws(AppError) -> Page<Character> {
        requestedPages.append(page)
        requestedFilters.append(filter)
        requestedFreshness.append(freshness)
        // The response is decided on entering the gate, not on leaving it: lets the
        // test change future answers without changing what's already in flight —
        // needed to distinguish a stale response from a fresh one.
        let result = charactersByPage[page] ?? charactersFallback
        await gate?.wait()
        return try result.get()
    }

    func character(id: Int) async throws(AppError) -> Character {
        requestedCharacterIDs.append(id)
        return try characterResult.get()
    }

    func episodes(ids: [Int]) async throws(AppError) -> [Episode] {
        requestedEpisodeIDs.append(ids)
        return try episodesResult.get()
    }
}

extension Character {
    // A valid character where each test only overrides what it cares about.
    static func stub(
        id: Int = 1,
        name: String = "Rick Sanchez",
        episodeIDs: [Int] = [1, 2]
    ) -> Character {
        Character(
            id: id,
            name: name,
            status: .alive,
            species: "Human",
            type: nil,
            gender: .male,
            origin: "Earth (C-137)",
            location: "Citadel of Ricks",
            // One avatar per id, like the API: lets a test tell one page's images
            // apart from the next's.
            imageURL: URL(string: "https://rickandmortyapi.com/api/character/avatar/\(id).jpeg"),
            episodeIDs: episodeIDs
        )
    }
}

extension Page where Item == Character {
    // A page of characters with sequential ids, so scrolling tests don't need
    // twenty hand-written stubs each time.
    static func stub(page: Int, totalPages: Int, ids: ClosedRange<Int>) -> Page<Character> {
        Page(
            items: ids.map { Character.stub(id: $0, name: "Character \($0)") },
            currentPage: page,
            totalPages: totalPages
        )
    }
}
