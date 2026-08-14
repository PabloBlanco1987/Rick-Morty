import Foundation

enum EpisodeMapper {
    static func map(_ dto: EpisodeDTO) -> Episode {
        Episode(
            id: dto.id,
            name: dto.name,
            code: dto.episode,
            airDate: try? airDateStrategy.parse(dto.airDate)
        )
    }

    /// The API writes air dates in US English (`"December 2, 2013"`) regardless of the
    /// device locale, so parsing is pinned to `en_US_POSIX`. Using `Date.ParseStrategy`
    /// instead of `DateFormatter` also sidesteps the latter's thread-safety caveat —
    /// the strategy is a `Sendable` value, so one shared instance is safe and there is
    /// no formatter allocation per episode.
    private static let airDateStrategy = Date.ParseStrategy(
        format: "\(month: .wide) \(day: .defaultDigits), \(year: .defaultDigits)",
        locale: Locale(identifier: "en_US_POSIX"),
        timeZone: .gmt
    )
}
