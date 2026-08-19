import Foundation
import Testing
@testable import RickAndMorty

@Suite("Default character repository")
struct DefaultCharacterRepositoryTests {
    private func makeSUT(_ outcome: StubHTTPClient.Outcome) -> DefaultCharacterRepository {
        DefaultCharacterRepository(remote: CharacterRemoteDataSource(client: StubHTTPClient([outcome])))
    }

    @Test("A listing is mapped into domain characters carrying the requested page")
    func mapsListing() async throws {
        // The API doesn't say which page it is, so the number has to be the one
        // requested: page 3 is used so a hardcoded literal can't pass by accident
        let page = try await makeSUT(.json(JSONFixtures.charactersPage))
            .characters(page: 3, filter: .empty, freshness: .acceptCached)

        #expect(page.items.map(\.name) == ["Rick Sanchez", "Morty Smith"])
        #expect(page.currentPage == 3)
        #expect(page.totalPages == 42)
        #expect(page.hasNextPage)
    }

    @Test("A search that matches nothing is an empty result that remembers its page, not an error")
    func notFoundOnListingBecomesEmptyPage() async throws {
        // The API answers ?name=zzzz with a 404, not an empty results. Letting that
        // pass as a failure would show an error screen for a normal search with no
        // matches, so it's translated here. The empty page keeps the requested number
        // — 7 — so Page.empty()'s default can't pass by accident.
        let page = try await makeSUT(.failure(.notFound))
            .characters(page: 7, filter: CharacterFilter(name: "zzzz"), freshness: .acceptCached)

        #expect(page.items.isEmpty)
        #expect(page.currentPage == 7)
        #expect(!page.hasNextPage)
    }

    @Test("Real failures on a listing are not swallowed by the 404 translation")
    func otherListingErrorsPropagate() async {
        let sut = makeSUT(.failure(.server(statusCode: 500)))

        await #expect(throws: AppError.server(statusCode: 500)) {
            _ = try await sut.characters(page: 1, filter: .empty, freshness: .acceptCached)
        }
    }

    @Test("A missing character stays a genuine notFound on the detail path")
    func notFoundOnDetailStaysAnError() async {
        // Same code, opposite meaning: nobody searched for character 9999, they
        // navigated to it, so here "nothing found" is a genuine error
        let sut = makeSUT(.failure(.notFound))

        await #expect(throws: AppError.notFound) {
            _ = try await sut.character(id: 9_999)
        }
    }

    @Test("A detail payload is mapped into a domain character")
    func mapsDetail() async throws {
        let character = try await makeSUT(.json(JSONFixtures.rick)).character(id: 1)

        #expect(character.name == "Rick Sanchez")
        #expect(character.status == .alive)
        #expect(character.episodeIDs == [1, 2])
    }

    @Test("Episodes are mapped, air dates included")
    func mapsEpisodes() async throws {
        let episodes = try await makeSUT(.json(JSONFixtures.episodeArray)).episodes(ids: [1, 2])

        #expect(episodes.map(\.code) == ["S01E01", "S01E02"])
        #expect(episodes.allSatisfy { $0.airDate != nil })
    }

    @Test("The freshness the caller asks for reaches the request")
    func forwardsTheFreshness() async throws {
        // The repository sits between the domain, which says "fresh", and the data
        // source, which translates that to HTTP. Fail to forward it and refresh becomes
        // a gesture with no effect.
        let stub = StubHTTPClient(json: JSONFixtures.charactersPage)
        let sut = DefaultCharacterRepository(remote: CharacterRemoteDataSource(client: stub))

        _ = try await sut.characters(page: 1, filter: .empty, freshness: .acceptCached)
        _ = try await sut.characters(page: 1, filter: .empty, freshness: .fresh)

        let policies = await stub.requestedEndpoints.map(\.cachePolicy)
        #expect(policies == [.useProtocolCachePolicy, .reloadRevalidatingCacheData])
    }
}
