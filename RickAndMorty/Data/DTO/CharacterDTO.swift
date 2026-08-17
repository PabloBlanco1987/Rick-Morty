import Foundation

// El personaje tal cual lo manda la API.
// Solo declaro los campos que uso; url, created y las url de origen y ubicación los
// ignoro en vez de arrastrarlos.
// Tener el DTO separado de Character es lo que permite que la API añada, renombre o
// afloje un campo sin que el cambio pase de CharacterMapper.
struct CharacterDTO: Decodable, Sendable, Equatable {
    let id: Int
    let name: String
    let status: String
    let species: String
    let type: String
    let gender: String
    let origin: PlaceDTO
    let location: PlaceDTO
    let image: String
    let episode: [String]
}

struct PlaceDTO: Decodable, Sendable, Equatable {
    let name: String
}
