import Foundation

// Episodio en el que sale un personaje
struct Episode: Identifiable, Hashable, Sendable {
    let id: Int
    let name: String
    // Código de temporada/episodio, tipo S01E01
    let code: String
    // nil si no se puede parsear la fecha que manda la API.
    // El formateo para el locale lo hace presentación, aquí no guardamos texto ya formateado.
    let airDate: Date?
}
