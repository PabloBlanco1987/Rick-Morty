import Foundation

/// Converts an episode DTO into a domain entity.
enum EpisodeMapper {
    static func map(_ dto: EpisodeDTO) -> Episode {
        Episode(
            id: dto.id,
            name: dto.name,
            code: dto.episode,
            airDate: try? airDateStrategy.parse(dto.airDate)
        )
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
