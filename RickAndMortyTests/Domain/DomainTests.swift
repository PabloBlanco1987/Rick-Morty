import Foundation
import Testing
@testable import RickAndMorty

@Suite("Page")
struct PageTests {
    @Test("Knows there is more to load while pages remain")
    func reportsNextPage() {
        let page = Page(items: [1, 2], currentPage: 1, totalPages: 42)
        #expect(page.hasNextPage)
        #expect(page.nextPage == 2)
    }

    @Test("Stops on the last page")
    func stopsOnLastPage() {
        let page = Page(items: [1], currentPage: 42, totalPages: 42)
        #expect(!page.hasNextPage)
        #expect(page.nextPage == nil)
    }

    @Test("An empty page never asks for more")
    func emptyPageHasNoNext() {
        let page = Page<Int>.empty(page: 3)
        #expect(page.items.isEmpty)
        #expect(page.currentPage == 3)
        #expect(!page.hasNextPage)
    }
}

@Suite("Character filter")
struct CharacterFilterTests {
    @Test("Whitespace is not a search term")
    func whitespaceOnlyNameIsEmpty() {
        let filter = CharacterFilter(name: "   \n ")
        #expect(filter.trimmedName.isEmpty)
        #expect(filter.isEmpty)
    }

    @Test("Any single criterion makes the filter active")
    func singleCriterionIsNotEmpty() {
        #expect(!CharacterFilter(name: "rick").isEmpty)
        #expect(!CharacterFilter(status: .alive).isEmpty)
        #expect(!CharacterFilter(gender: .female).isEmpty)
        #expect(!CharacterFilter(species: "Human").isEmpty)
    }

    @Test("The default filter is inert")
    func emptyIsInert() {
        #expect(CharacterFilter.empty.isEmpty)
    }

    @Test("Normalizing trims what was typed and leaves the rest alone")
    func normalizedTrimsTheTypedFields() {
        // This is how criteria get compared: whoever decides a reload is needed and
        // whoever decides a response is still valid must see the same filter, or one
        // extra space would discard a good response
        let typed = CharacterFilter(name: "  rick ", status: .alive, gender: .male, species: " Human\n")

        #expect(typed.normalized == CharacterFilter(name: "rick", status: .alive, gender: .male, species: "Human"))
        #expect(typed.normalized.normalized == typed.normalized)
    }
}

@Suite("App error")
struct AppErrorTests {
    @Test("Only what can fix itself by waiting is retried automatically", arguments: [
        (AppError.timeout, true),
        (AppError.rateLimited, true),
        (AppError.server(statusCode: 500), true),
        (AppError.server(statusCode: 503), true),
        (AppError.server(statusCode: 400), false),
        (AppError.offline, false),
        (AppError.notFound, false),
        (AppError.decoding, false),
        (AppError.cancelled, false),
        (AppError.unknown, false),
    ])
    func retryability(error: AppError, expected: Bool) {
        #expect(error.isRetryable == expected)
    }

    @Test("Being told to slow down earns more patience than a server stumble")
    func rateLimitingWaitsLonger() {
        // Retrying a "you're going too fast" at 300ms just extends the punishment
        #expect(AppError.rateLimited.retryPatience == .backOff)
        #expect(AppError.server(statusCode: 500).retryPatience == .brief)
        #expect(AppError.timeout.retryPatience == .brief)
    }
}

@Suite("Fetch character detail use case")
struct FetchCharacterDetailUseCaseTests {
    @Test("Fetches exactly the episodes the character appears in")
    func requestsTheCharactersEpisodes() async throws {
        let repository = StubCharacterRepository(
            character: .success(.stub(episodeIDs: [1, 2, 51])),
            episodes: .success([
                Episode(id: 1, name: "Pilot", code: "S01E01", airDate: nil),
                Episode(id: 2, name: "Lawnmower Dog", code: "S01E02", airDate: nil),
                Episode(id: 51, name: "Rickmurai Jack", code: "S05E10", airDate: nil),
            ])
        )
        let sut = FetchCharacterDetailUseCase(repository: repository)

        let detail = try await sut.execute(id: 1)

        #expect(detail.character.id == 1)
        #expect(detail.episodes.map(\.id) == [1, 2, 51])
        await #expect(repository.requestedEpisodeIDs == [[1, 2, 51]])
    }

    @Test("Skips the episode request entirely when there are none")
    func skipsEmptyEpisodeRequest() async throws {
        let repository = StubCharacterRepository(character: .success(.stub(episodeIDs: [])))
        let sut = FetchCharacterDetailUseCase(repository: repository)

        let detail = try await sut.execute(id: 1)

        #expect(detail.episodes.isEmpty)
        await #expect(repository.episodesCallCount == 0)
    }

    @Test("Propagates a missing character rather than inventing one")
    func propagatesNotFound() async {
        let repository = StubCharacterRepository(character: .failure(.notFound))
        let sut = FetchCharacterDetailUseCase(repository: repository)

        await #expect(throws: AppError.notFound) {
            _ = try await sut.execute(id: 9_999)
        }
    }

    @Test("The detail is all or nothing: if the episodes fail, the use case fails")
    func episodesFailureFailsTheDetail() async {
        // Keeping the character already on screen is the view model's job; the use
        // case returns the full detail or nothing, so there's no half-built type
        let repository = StubCharacterRepository(
            character: .success(.stub(episodeIDs: [1, 2])),
            episodes: .failure(.offline)
        )
        let sut = FetchCharacterDetailUseCase(repository: repository)

        await #expect(throws: AppError.offline) {
            _ = try await sut.execute(id: 1)
        }
    }
}

@Suite("Fetch characters use case")
struct FetchCharactersUseCaseTests {
    @Test("Asks the repository for the page and the filter it was given, untouched")
    func forwardsThePageAndTheFilter() async throws {
        let expected = Page(items: [Character.stub()], currentPage: 3, totalPages: 42)
        let repository = StubCharacterRepository(characters: .success(expected))
        let sut = FetchCharactersUseCase(repository: repository)

        let page = try await sut.execute(page: 3, filter: CharacterFilter(name: "rick"))

        #expect(page == expected)
        await #expect(repository.requestedPages == [3])
        await #expect(repository.requestedFilters == [CharacterFilter(name: "rick")])
    }

    @Test("Passes the freshness through, and settles for the cache unless told otherwise")
    func forwardsTheFreshness() async throws {
        // Only pull-to-refresh asks for fresh data; every other load settles for the
        // cache, which is what makes returning from the detail screen free of a
        // request. If the use case dropped that flag along the way, the refresh
        // gesture wouldn't refresh anything.
        let repository = StubCharacterRepository()
        let sut = FetchCharactersUseCase(repository: repository)

        _ = try await sut.execute(page: 1, filter: .empty)
        _ = try await sut.execute(page: 1, filter: .empty, freshness: .fresh)

        await #expect(repository.requestedFreshness == [.acceptCached, .fresh])
    }
}
