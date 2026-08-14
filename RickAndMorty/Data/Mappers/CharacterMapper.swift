import Foundation

// Convierte lo que llega de la API en entidades de dominio.
// El mapeo no falla nunca: un status desconocido pasa a .unknown, una imagen que no
// es URL pasa a nil, un type vacío pasa a nil. Un registro raro no puede costarle al
// usuario la página entera de resultados.
enum CharacterMapper {
    static func map(_ dto: CharacterDTO) -> Character {
        Character(
            id: dto.id,
            name: dto.name,
            status: Character.Status(rawValue: dto.status.lowercased()) ?? .unknown,
            species: dto.species,
            type: dto.type.isEmpty ? nil : dto.type,
            gender: Character.Gender(rawValue: dto.gender.lowercased()) ?? .unknown,
            origin: dto.origin.name,
            location: dto.location.name,
            imageURL: URL(string: dto.image),
            episodeIDs: episodeIDs(from: dto.episode)
        )
    }

    static func map(_ dto: PageDTO<CharacterDTO>, page: Int) -> Page<Character> {
        Page(
            items: dto.results.map(map),
            currentPage: page,
            totalPages: dto.info.pages,
            totalCount: dto.info.count
        )
    }

    // La API devuelve enlaces a los episodios y el dominio quiere ids. Lo que no
    // acaba en un entero lo descarto, antes que meter un id equivocado por defecto.
    private static func episodeIDs(from urls: [String]) -> [Int] {
        urls.compactMap { Int(URL(string: $0)?.lastPathComponent ?? "") }
    }
}
