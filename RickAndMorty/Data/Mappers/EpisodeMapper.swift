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

    // Las fechas de emisión vienen siempre en inglés de EE. UU. ("December 2, 2013"),
    // dé igual el locale del dispositivo, así que fijo el parseo a en_US_POSIX.
    // Uso Date.ParseStrategy en vez de DateFormatter porque es Sendable: una sola
    // instancia compartida es segura y no creo un formatter por episodio.
    private static let airDateStrategy = Date.ParseStrategy(
        format: "\(month: .wide) \(day: .defaultDigits), \(year: .defaultDigits)",
        locale: Locale(identifier: "en_US_POSIX"),
        timeZone: .gmt
    )
}
