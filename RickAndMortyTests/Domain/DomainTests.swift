import Foundation
import Testing
@testable import RickAndMorty

@Suite("Page")
struct PageTests {
    @Test("Knows there is more to load while pages remain")
    func reportsNextPage() {
        let page = Page(items: [1, 2], currentPage: 1, totalPages: 42, totalCount: 826)
        #expect(page.hasNextPage)
        #expect(page.nextPage == 2)
    }

    @Test("Stops on the last page")
    func stopsOnLastPage() {
        let page = Page(items: [1], currentPage: 42, totalPages: 42, totalCount: 826)
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
    func noneIsEmpty() {
        #expect(CharacterFilter.none.isEmpty)
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
        // Reintentar un "vas demasiado rápido" a los 300 ms es alargarse el castigo
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

        #expect(detail.episodes.count == 3)
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
}

@Suite("Fetch characters use case")
struct FetchCharactersUseCaseTests {
    @Test("Asks the repository for the page it was given")
    func forwardsThePage() async throws {
        let expected = Page(items: [Character.stub()], currentPage: 3, totalPages: 42, totalCount: 826)
        let repository = StubCharacterRepository(characters: .success(expected))
        let sut = FetchCharactersUseCase(repository: repository)

        let page = try await sut.execute(page: 3, filter: CharacterFilter(name: "rick"))

        #expect(page == expected)
        await #expect(repository.requestedPages == [3])
    }
}
