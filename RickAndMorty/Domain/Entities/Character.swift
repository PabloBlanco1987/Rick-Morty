import Foundation

// Personaje tal y como lo usa el resto de la app.
// Aquí no hay nada de transporte: ni strings haciendo de URL, ni "" haciendo de nulo.
// De limpiar lo que manda la API ya se encargan CharacterDTO y CharacterMapper.
struct Character: Identifiable, Hashable, Sendable {
    let id: Int
    let name: String
    let status: Status
    let species: String
    // La API manda "" cuando no hay subespecie; aquí es nil
    let type: String?
    let gender: Gender
    // La API manda el literal "unknown" cuando no lo sabe; aquí es nil, igual que el
    // type vacío: los centinelas se limpian en el mapper y no en cada sitio que los pinta
    let origin: String?
    let location: String?
    // nil si lo que llega no es una URL válida. La UI tiene placeholder,
    // así que se ve peor pero no perdemos el personaje.
    let imageURL: URL?
    let episodeIDs: [Int]
}

extension Character {
    // Conjunto cerrado: un valor raro de la API cae en .unknown y no tira la página entera
    enum Status: String, Hashable, Sendable, CaseIterable {
        case alive, dead, unknown
    }

    enum Gender: String, Hashable, Sendable, CaseIterable {
        case female, male, genderless, unknown
    }
}
