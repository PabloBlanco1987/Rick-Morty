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
        let page = try await makeSUT(.json(JSONFixtures.charactersPage)).characters(page: 1, filter: .none)

        #expect(page.items.map(\.name) == ["Rick Sanchez", "Morty Smith"])
        #expect(page.totalPages == 42)
        #expect(page.hasNextPage)
    }

    @Test("A search that matches nothing is an empty result, not an error")
    func notFoundOnListingBecomesEmptyPage() async throws {
        // The API answers `?name=zzzz` with 404 rather than an empty `results` array.
        // Surfacing that as a failure would show an error screen for an ordinary
        // "no matches" search, so it is translated here.
        let page = try await makeSUT(.failure(.notFound)).characters(page: 1, filter: CharacterFilter(name: "zzzz"))

        #expect(page.items.isEmpty)
        #expect(page.currentPage == 1)
        #expect(!page.hasNextPage)
    }

    @Test("The empty page keeps the page number that was asked for")
    func emptyPageRemembersItsPage() async throws {
        let page = try await makeSUT(.failure(.notFound)).characters(page: 7, filter: CharacterFilter(name: "zzzz"))
        #expect(page.currentPage == 7)
    }

    @Test("Real failures on a listing are not swallowed by the 404 translation")
    func otherListingErrorsPropagate() async {
        let sut = makeSUT(.failure(.server(statusCode: 500)))

        await #expect(throws: AppError.server(statusCode: 500)) {
            _ = try await sut.characters(page: 1, filter: .none)
        }
    }

    @Test("A missing character stays a genuine notFound on the detail path")
    func notFoundOnDetailStaysAnError() async {
        // Same status code, opposite meaning: nobody searched for character 9999,
        // they navigated to it, so "there is nothing here" is a real error.
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
}
