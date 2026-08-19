import Foundation

/// Converts an episode DTO into a domain entity.
enum EpisodeMapper {
    static func map(_ dto: EpisodeDTO) -> Episode {
        Episode(
            id: dto.id,
            name: dto.name,
            code: parseCode(dto.episode),
            airDate: try? airDateStrategy.parse(dto.airDate)
        )
    }

    // "S01E08" → season 1, episode 8. Two markers around two numbers, which is exactly
    // what a `split` says; a regex would describe the same shape with more machinery.
    //
    // An unreadable code is nil rather than half a code, the same rule the air date
    // follows below: the row then shows the episode without saying where it sits, which
    // beats claiming a season nobody sent.
    private static func parseCode(_ code: String) -> Episode.Code? {
        guard code.first == "S" else { return nil }

        let parts = code.dropFirst().split(separator: "E", omittingEmptySubsequences: false)

        guard parts.count == 2,
              let season = digits(parts[0]),
              let number = digits(parts[1])
        else { return nil }

        return Episode.Code(season: season, number: number)
    }

    // Digits and nothing else: `Int` on its own accepts a sign, so "S-1E8" would map to
    // season minus one instead of being rejected.
    private static func digits(_ text: Substring) -> Int? {
        text.allSatisfy { $0.isASCII && $0.isNumber } ? Int(text) : nil
    }

    // Air dates always arrive as US English ("December 2, 2013"), regardless of device
    // locale, so parsing is pinned to en_US_POSIX. Date.ParseStrategy over DateFormatter
    // because it's Sendable — one shared instance, no formatter built per episode.
    private static let airDateStrategy = Date.ParseStrategy(
        format: "\(month: .wide) \(day: .defaultDigits), \(year: .defaultDigits)",
        locale: Locale(identifier: "en_US_POSIX"),
        timeZone: .gmt
    )
}
