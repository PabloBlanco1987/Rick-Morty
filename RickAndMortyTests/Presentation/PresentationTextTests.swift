import Foundation
import Testing
import UIKit
@testable import RickAndMorty

/// What presentation decides about how each thing reads: error text, status and
/// gender names, and the air date. Wording itself isn't checked — that's expected to
/// change — but what can break silently: a misspelled SF Symbol renders as nothing,
/// two cases sharing text hide a copy-paste, and a date formatted in the wrong time
/// zone shows a day early.
@Suite("Error presentation")
struct AppErrorPresentationTests {
    private static let everyError: [AppError] = [
        .offline, .timeout, .notFound, .rateLimited, .server(statusCode: 500), .decoding, .cancelled, .unknown,
    ]

    @Test("Every error icon is a symbol that exists", arguments: everyError)
    func everyIconExists(error: AppError) {
        // A misspelled SF Symbol name doesn't fail to compile — the view renders a
        // blank. This is the one place all eight can be checked at once.
        #expect(UIImage(systemName: error.systemImage) != nil, "\(error.systemImage) is not an SF Symbol")
    }

    @Test("Every error says what happened and what to do, in two different sentences", arguments: everyError)
    func everyErrorHasATitleAndAMessage(error: AppError) {
        #expect(!error.title.isEmpty)
        #expect(!error.message.isEmpty)
        #expect(error.title != error.message)
    }

    @Test("Each error the user can tell apart reads differently")
    func distinctErrorsReadDifferently() {
        // Cancelled and unknown share text on purpose — neither has anything concrete
        // to say; the rest each have their own cause and fix, and a match between two
        // would mean a copied key wasn't changed.
        let distinct: [AppError] = [.offline, .timeout, .notFound, .rateLimited, .server(statusCode: 500), .decoding]

        #expect(Set(distinct.map(\.title)).count == distinct.count)
        #expect(Set(distinct.map(\.message)).count == distinct.count)
        #expect(AppError.cancelled.title == AppError.unknown.title)
    }
}

@Suite("Status and gender names")
struct CharacterEnumDisplayNameTests {
    @Test("Every status has a name of its own")
    func statusesReadDifferently() {
        // The badge states status as text because color doesn't reach everyone; if two
        // statuses shared text, those users couldn't tell them apart.
        let names = Character.Status.allCases.map(\.displayName)
        #expect(names.allSatisfy { !$0.isEmpty })
        #expect(Set(names).count == names.count)
    }

    @Test("Every gender has a name of its own")
    func gendersReadDifferently() {
        let names = Character.Gender.allCases.map(\.displayName)
        #expect(names.allSatisfy { !$0.isEmpty })
        #expect(Set(names).count == names.count)
    }
}

/// Serialized because the second test changes the process time zone for its duration —
/// it restores it on exit, but can't run alongside another test that also touches it.
/// It's the only test in the suite that formats a date without pinning the zone, on
/// purpose.
@Suite("Episode air date formatting", .serialized)
struct EpisodeAirDateFormattingTests {
    // December 2, 2013 at midnight GMT, matching how the mapper stores it
    private var pilotAirDate: Date {
        get throws {
            var components = DateComponents()
            components.year = 2013
            components.month = 12
            components.day = 2
            components.timeZone = .gmt
            return try #require(Calendar(identifier: .gregorian).date(from: components))
        }
    }

    @Test("An unknown air date has no text, rather than a placeholder date")
    func unknownAirDateHasNoText() {
        let pilot = Episode(id: 1, name: "Pilot", code: Episode.Code(season: 1, number: 1), airDate: nil)

        #expect(pilot.formattedAirDate == nil)
    }

    @Test("The air date reads as the day it aired, even where midnight GMT is still the day before")
    func airDateDoesNotShiftWestOfGreenwich() throws {
        // The date is stored as midnight that day in GMT. Formatted in the device's
        // zone, any zone with a negative offset shifts that midnight to the day
        // before, so the pilot would show as aired December 1. The process is set to
        // Honolulu — ten hours west — and checked that it still reads 2.
        //
        // The process zone is changed via the TZ env var, the only thing Foundation
        // re-reads: NSTimeZone.default no longer updates TimeZone.current. That's what
        // makes this test valid on any machine, not just west of Greenwich.
        //
        // The text is re-parsed with the same style instead of compared to a literal,
        // so the test doesn't depend on the device's language.
        let previous = getenv("TZ").map { String(cString: $0) }
        setenv("TZ", "Pacific/Honolulu", 1)
        NSTimeZone.resetSystemTimeZone()
        defer {
            if let previous { setenv("TZ", previous, 1) } else { unsetenv("TZ") }
            NSTimeZone.resetSystemTimeZone()
        }
        // If the change had no effect, the test would pass without testing anything —
        // check it
        try #require(TimeZone.current.identifier == "Pacific/Honolulu")

        let episode = Episode(id: 1, name: "Pilot", code: Episode.Code(season: 1, number: 1), airDate: try pilotAirDate)
        let text = try #require(episode.formattedAirDate)
        let shown = try Date.FormatStyle(timeZone: .gmt).day().month(.abbreviated).year().parse(text)
        let components = Calendar(identifier: .gregorian).dateComponents(in: .gmt, from: shown)

        #expect(components.day == 2, "The air date was shown as \(text)")
        #expect(components.month == 12)
        #expect(components.year == 2013)
    }
}
