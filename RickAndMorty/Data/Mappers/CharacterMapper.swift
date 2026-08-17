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
            origin: placeName(dto.origin.name),
            location: placeName(dto.location.name),
            imageURL: imageURL(from: dto.image),
            episodeIDs: episodeIDs(from: dto.episode)
        )
    }

    static func map(_ dto: PageDTO<CharacterDTO>, page: Int) -> Page<Character> {
        Page(
            items: dto.results.map(map),
            currentPage: page,
            totalPages: dto.info.pages
        )
    }

    // "unknown" es el centinela de la API para un lugar que no sabe —viene así, en
    // minúscula y sin url—; en el dominio la ausencia es nil, no un texto que cada
    // pantalla tendría que reconocer y traducir por su cuenta
    private static func placeName(_ raw: String) -> String? {
        raw == "unknown" ? nil : raw
    }

    // Solo vale una URL absoluta con esquema y host. Desde iOS 17, URL(string:) acepta
    // casi cualquier texto —"not a url" pasa como referencia relativa y solo "" da nil—,
    // así que sin esta comprobación la promesa de "nil si no es una URL válida" no la
    // cumplía nadie, y el fallo aparecía después, en la descarga, en vez de aquí.
    private static func imageURL(from raw: String) -> URL? {
        guard let url = URL(string: raw), url.scheme != nil, url.host() != nil else { return nil }
        return url
    }

    // La API devuelve enlaces a los episodios y el dominio quiere ids. Lo que no
    // acaba en un entero lo descarto, antes que meter un id equivocado por defecto.
    private static func episodeIDs(from urls: [String]) -> [Int] {
        urls.compactMap { Int(URL(string: $0)?.lastPathComponent ?? "") }
    }
}
