#if DEBUG
import Foundation

/// Fixed-data launch, debug builds only.
///
/// For UI tests: hitting the real API means flaky failures from no network, rate
/// limits, or someone adding a character — none of which mean anything broke.
/// Swapping the repository behind the same protocol keeps the app identical; only
/// where the bytes come from changes.
enum LaunchEnvironment {
    // Passed by the test as a launch argument
    static let stubbedFlag = "-stubbed-data"
    // Same stubbed data, but pull-to-refresh fails. The only way a UI test can
    // exercise the refresh-failure notice without depending on there being no network.
    static let refreshFailsFlag = "-stubbed-refresh-fails"

    static var isStubbed: Bool {
        ProcessInfo.processInfo.arguments.contains(stubbedFlag)
    }

    static var refreshFails: Bool {
        ProcessInfo.processInfo.arguments.contains(refreshFailsFlag)
    }
}

/// Same contract as the real repository, resolved in memory: pages, filters by the
/// same criteria, answers detail lookups. The app can't tell where the data comes from.
struct StubbedCharacterRepository: CharacterRepository {
    private static let pageSize = 20

    // Whether requests demanding fresh data — only refresh makes those — fail.
    // Lets tests verify the list is kept and the failure notice fires.
    let refreshFails: Bool

    init(refreshFails: Bool = false) {
        self.refreshFails = refreshFails
    }

    // The four filterable fields. A named type, not a tuple, so the table below
    // reads without counting positions.
    private struct Seed {
        let name: String
        let status: Character.Status
        let species: String
        let gender: Character.Gender
    }

    private let all: [Character] = {
        let seeds = [
            Seed(name: "Rick Sanchez", status: .alive, species: "Human", gender: .male),
            Seed(name: "Morty Smith", status: .alive, species: "Human", gender: .male),
            Seed(name: "Summer Smith", status: .alive, species: "Human", gender: .female),
            Seed(name: "Beth Smith", status: .alive, species: "Human", gender: .female),
            Seed(name: "Jerry Smith", status: .alive, species: "Human", gender: .male),
            Seed(name: "Abadango Cluster Princess", status: .alive, species: "Alien", gender: .female),
            Seed(name: "Bird Person", status: .dead, species: "Alien", gender: .male),
            Seed(name: "Squanchy", status: .alive, species: "Alien", gender: .male),
            Seed(name: "Mr. Meeseeks", status: .unknown, species: "Humanoid", gender: .male),
            Seed(name: "Tammy Guetermann", status: .dead, species: "Human", gender: .female),
            Seed(name: "Scary Terry", status: .alive, species: "Humanoid", gender: .male),
            Seed(name: "Snowball", status: .alive, species: "Animal", gender: .male),
            Seed(name: "Krombopulos Michael", status: .dead, species: "Alien", gender: .male),
            Seed(name: "Zeep Xanflorp", status: .alive, species: "Alien", gender: .male),
            Seed(name: "Unity", status: .unknown, species: "Alien", gender: .genderless),
            Seed(name: "Noob-Noob", status: .alive, species: "Humanoid", gender: .male),
            Seed(name: "Evil Morty", status: .alive, species: "Human", gender: .male),
            Seed(name: "Pickle Rick", status: .alive, species: "Human", gender: .male),
            Seed(name: "Mr. Poopybutthole", status: .alive, species: "Poopybutthole", gender: .male),
            Seed(name: "Jaguar", status: .alive, species: "Human", gender: .male),
            Seed(name: "Supernova", status: .alive, species: "Alien", gender: .female),
            Seed(name: "Vance Maximus", status: .dead, species: "Human", gender: .male),
            Seed(name: "Million Ants", status: .dead, species: "Animal", gender: .genderless),
            Seed(name: "Glootie", status: .alive, species: "Alien", gender: .male),
            Seed(name: "Birdperson's Wife", status: .unknown, species: "Alien", gender: .female),
        ]

        return seeds.enumerated().map { index, seed in
            Character(
                id: index + 1,
                name: seed.name,
                status: seed.status,
                species: seed.species,
                type: nil,
                gender: seed.gender,
                origin: "Earth (C-137)",
                location: "Citadel of Ricks",
                // No URL on purpose: a UI test can't depend on images downloading,
                // so cells show their placeholder.
                imageURL: nil,
                episodeIDs: Array(1...((index % 4) + 1))
            )
        }
    }()

    // freshness doesn't change the answer — nothing in memory is fresher than
    // itself — except when refresh is set to fail.
    func characters(
        page: Int,
        filter: CharacterFilter,
        freshness: Freshness
    ) async throws(AppError) -> Page<Character> {
        if refreshFails, freshness == .fresh {
            throw .offline
        }

        // Same criteria the server applies, the same way: partial match,
        // case-insensitive.
        let matches = all.filter { character in
            let name = filter.trimmedName
            let species = filter.trimmedSpecies

            return (name.isEmpty || character.name.localizedCaseInsensitiveContains(name))
                && (species.isEmpty || character.species.localizedCaseInsensitiveContains(species))
                && (filter.status == nil || character.status == filter.status)
                && (filter.gender == nil || character.gender == filter.gender)
        }

        let totalPages = max(1, Int((Double(matches.count) / Double(Self.pageSize)).rounded(.up)))
        let start = (page - 1) * Self.pageSize
        guard start < matches.count else { return .empty(page: page) }

        return Page(
            items: Array(matches[start..<min(start + Self.pageSize, matches.count)]),
            currentPage: page,
            totalPages: totalPages
        )
    }

    func character(id: Int) async throws(AppError) -> Character {
        guard let character = all.first(where: { $0.id == id }) else { throw .notFound }
        return character
    }

    func episodes(ids: [Int]) async throws(AppError) -> [Episode] {
        ids.map { id in
            Episode(
                id: id,
                name: "Episode \(id)",
                code: Episode.Code(season: 1, number: id),
                airDate: Date(timeIntervalSince1970: 1_386_000_000)
            )
        }
    }
}
#endif
