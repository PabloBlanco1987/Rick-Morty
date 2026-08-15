#if DEBUG
import Foundation

// Arranque con datos fijos, solo en compilaciones de depuración.
//
// Existe para los tests de UI. Un test de interfaz que hable con la API de verdad falla
// el día que no hay red, el día que la API contesta 429 —que con este proyecto es
// cualquier día— y el día que alguien añade un personaje: tres formas de que la suite
// se ponga roja sin que nadie haya roto nada. Con el grafo montado sobre este
// repositorio la app es exactamente la misma, la única diferencia es de dónde salen los
// bytes, que es justo lo que la inyección por protocolos estaba para permitir.
//
// Va dentro de #if DEBUG para que no viaje en el binario que se publica.
enum LaunchEnvironment {
    // Lo pasa el test como argumento de lanzamiento
    static let stubbedFlag = "-stubbed-data"

    static var isStubbed: Bool {
        ProcessInfo.processInfo.arguments.contains(stubbedFlag)
    }
}

// Los mismos contratos que el repositorio de verdad, resueltos en memoria: pagina,
// filtra por los mismos criterios y contesta al detalle. Lo que la app no puede notar
// es de dónde vienen los datos.
struct StubbedCharacterRepository: CharacterRepository {
    private static let pageSize = 20

    // Los cuatro campos por los que se puede filtrar. Es un tipo con nombre y no una
    // tupla para que la tabla de abajo se lea sin tener que contar posiciones.
    private struct Seed {
        let name: String
        let status: Character.Status
        let species: String
        let gender: Character.Gender
    }

    private let all: [Character] = {
        let seeds = [
            Seed(name: "Rick Sanchez", status: .alive, species: "Human", gender: .male),
            Seed(name: "Morty Smith", status: .alive, species: "Human", gender: .male),
            Seed(name: "Summer Smith", status: .alive, species: "Human", gender: .female),
            Seed(name: "Beth Smith", status: .alive, species: "Human", gender: .female),
            Seed(name: "Jerry Smith", status: .alive, species: "Human", gender: .male),
            Seed(name: "Abadango Cluster Princess", status: .alive, species: "Alien", gender: .female),
            Seed(name: "Bird Person", status: .dead, species: "Alien", gender: .male),
            Seed(name: "Squanchy", status: .alive, species: "Alien", gender: .male),
            Seed(name: "Mr. Meeseeks", status: .unknown, species: "Humanoid", gender: .male),
            Seed(name: "Tammy Guetermann", status: .dead, species: "Human", gender: .female),
            Seed(name: "Scary Terry", status: .alive, species: "Humanoid", gender: .male),
            Seed(name: "Snowball", status: .alive, species: "Animal", gender: .male),
            Seed(name: "Krombopulos Michael", status: .dead, species: "Alien", gender: .male),
            Seed(name: "Zeep Xanflorp", status: .alive, species: "Alien", gender: .male),
            Seed(name: "Unity", status: .unknown, species: "Alien", gender: .genderless),
            Seed(name: "Noob-Noob", status: .alive, species: "Humanoid", gender: .male),
            Seed(name: "Evil Morty", status: .alive, species: "Human", gender: .male),
            Seed(name: "Pickle Rick", status: .alive, species: "Human", gender: .male),
            Seed(name: "Mr. Poopybutthole", status: .alive, species: "Poopybutthole", gender: .male),
            Seed(name: "Jaguar", status: .alive, species: "Human", gender: .male),
            Seed(name: "Supernova", status: .alive, species: "Alien", gender: .female),
            Seed(name: "Vance Maximus", status: .dead, species: "Human", gender: .male),
            Seed(name: "Million Ants", status: .dead, species: "Animal", gender: .genderless),
            Seed(name: "Glootie", status: .alive, species: "Alien", gender: .male),
            Seed(name: "Birdperson's Wife", status: .unknown, species: "Alien", gender: .female),
        ]

        return seeds.enumerated().map { index, seed in
            Character(
                id: index + 1,
                name: seed.name,
                status: seed.status,
                species: seed.species,
                type: nil,
                gender: seed.gender,
                origin: "Earth (C-137)",
                location: "Citadel of Ricks",
                // Sin URL a propósito: un test de UI no puede depender de que se
                // descarguen imágenes, así que las celdas enseñan su placeholder
                imageURL: nil,
                episodeIDs: Array(1...((index % 4) + 1))
            )
        }
    }()

    func characters(page: Int, filter: CharacterFilter) async throws(AppError) -> Page<Character> {
        // Los mismos criterios que aplica el servidor, y como él: por coincidencia
        // parcial y sin distinguir mayúsculas
        let matches = all.filter { character in
            let name = filter.trimmedName
            let species = filter.trimmedSpecies

            return (name.isEmpty || character.name.localizedCaseInsensitiveContains(name))
                && (species.isEmpty || character.species.localizedCaseInsensitiveContains(species))
                && (filter.status == nil || character.status == filter.status)
                && (filter.gender == nil || character.gender == filter.gender)
        }

        let totalPages = max(1, Int((Double(matches.count) / Double(Self.pageSize)).rounded(.up)))
        let start = (page - 1) * Self.pageSize
        guard start < matches.count else { return .empty(page: page) }

        return Page(
            items: Array(matches[start..<min(start + Self.pageSize, matches.count)]),
            currentPage: page,
            totalPages: totalPages,
            totalCount: matches.count
        )
    }

    func character(id: Int) async throws(AppError) -> Character {
        guard let character = all.first(where: { $0.id == id }) else { throw .notFound }
        return character
    }

    func episodes(ids: [Int]) async throws(AppError) -> [Episode] {
        ids.map { id in
            Episode(
                id: id,
                name: "Episode \(id)",
                code: String(format: "S01E%02d", id),
                airDate: Date(timeIntervalSince1970: 1_386_000_000)
            )
        }
    }
}
#endif
