import Foundation

struct EpisodeDTO: Decodable, Sendable, Equatable {
    let id: Int
    let name: String
    // En el JSON es air_date, tipo "December 2, 2013". Lo resuelve la estrategia
    // convertFromSnakeCase, no un CodingKeys a mano
    let airDate: String
    // Código de temporada/episodio, tipo "S01E01"
    let episode: String
}
