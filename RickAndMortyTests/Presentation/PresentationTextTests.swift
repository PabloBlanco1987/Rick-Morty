import Foundation
import Testing
import UIKit
@testable import RickAndMorty

// Lo que presentación decide sobre cómo se dice cada cosa: los textos de error, los
// nombres de estado y género, y la fecha de emisión. No se comprueba la redacción —eso
// es lo que cambia— sino lo que se puede romper sin que nadie lo vea: un símbolo SF mal
// escrito se pinta como nada, dos casos que dicen lo mismo esconden un copia y pega, y una
// fecha formateada en la zona equivocada sale un día antes.
@Suite("Error presentation")
struct AppErrorPresentationTests {
    private static let everyError: [AppError] = [
        .offline, .timeout, .notFound, .rateLimited, .server(statusCode: 500), .decoding, .cancelled, .unknown,
    ]

    @Test("Every error icon is a symbol that exists", arguments: everyError)
    func everyIconExists(error: AppError) {
        // Un nombre de SF Symbol con una errata no falla al compilar: la vista pinta un
        // hueco. Es el único sitio donde se pueden comprobar los ocho de una vez.
        #expect(UIImage(systemName: error.systemImage) != nil, "\(error.systemImage) is not an SF Symbol")
    }

    @Test("Every error says what happened and what to do, in two different sentences", arguments: everyError)
    func everyErrorHasATitleAndAMessage(error: AppError) {
        #expect(!error.title.isEmpty)
        #expect(!error.message.isEmpty)
        #expect(error.title != error.message)
    }

    @Test("Each error the user can tell apart reads differently")
    func distinctErrorsReadDifferently() {
        // Cancelar y desconocido comparten texto a propósito —ninguno de los dos tiene
        // nada concreto que contar—; los demás tienen cada uno su causa y su remedio, y si
        // dos coincidieran sería porque alguien copió una clave sin cambiar la otra
        let distinct: [AppError] = [.offline, .timeout, .notFound, .rateLimited, .server(statusCode: 500), .decoding]

        #expect(Set(distinct.map(\.title)).count == distinct.count)
        #expect(Set(distinct.map(\.message)).count == distinct.count)
        #expect(AppError.cancelled.title == AppError.unknown.title)
    }
}

@Suite("Status and gender names")
struct CharacterEnumDisplayNameTests {
    @Test("Every status has a name of its own")
    func statusesReadDifferently() {
        // El badge dice el estado con texto porque el color no llega a todo el mundo; si
        // dos estados compartieran texto, para esos usuarios serían el mismo
        let names = Character.Status.allCases.map(\.displayName)
        #expect(names.allSatisfy { !$0.isEmpty })
        #expect(Set(names).count == names.count)
    }

    @Test("Every gender has a name of its own")
    func gendersReadDifferently() {
        let names = Character.Gender.allCases.map(\.displayName)
        #expect(names.allSatisfy { !$0.isEmpty })
        #expect(Set(names).count == names.count)
    }
}

// Serializada porque el segundo test cambia la zona horaria del proceso mientras dura, y
// aunque la restaura al salir, no puede correr a la vez que otro que también la toque.
// Es el único test de la suite que formatea una fecha sin fijar la zona a propósito.
@Suite("Episode air date formatting", .serialized)
struct EpisodeAirDateFormattingTests {
    // El día 2 de diciembre de 2013 a medianoche en GMT, que es como lo guarda el mapper
    private var pilotAirDate: Date {
        get throws {
            var components = DateComponents()
            components.year = 2013
            components.month = 12
            components.day = 2
            components.timeZone = .gmt
            return try #require(Calendar(identifier: .gregorian).date(from: components))
        }
    }

    @Test("An unknown air date has no text, rather than a placeholder date")
    func unknownAirDateHasNoText() {
        #expect(Episode(id: 1, name: "Pilot", code: "S01E01", airDate: nil).formattedAirDate == nil)
    }

    @Test("The air date reads as the day it aired, even where midnight GMT is still the day before")
    func airDateDoesNotShiftWestOfGreenwich() throws {
        // La fecha se guarda como la medianoche de ese día en GMT. Formateada en la zona
        // del dispositivo, en cualquier zona con desfase negativo esa medianoche cae el
        // día anterior y el piloto saldría emitido el 1 de diciembre. Se pone el proceso
        // en Honolulu —diez horas al oeste— y se comprueba que sigue diciendo 2.
        //
        // La zona del proceso se cambia por la variable TZ, que es lo único que Foundation
        // relee: NSTimeZone.default ya no cambia TimeZone.current. Es lo que hace que este
        // test valga en cualquier máquina y no solo al oeste de Greenwich.
        //
        // El texto se vuelve a parsear con el mismo estilo en vez de compararlo con un
        // literal: así el test no depende del idioma del dispositivo en el que corra.
        let previous = getenv("TZ").map { String(cString: $0) }
        setenv("TZ", "Pacific/Honolulu", 1)
        NSTimeZone.resetSystemTimeZone()
        defer {
            if let previous { setenv("TZ", previous, 1) } else { unsetenv("TZ") }
            NSTimeZone.resetSystemTimeZone()
        }
        // Si el cambio no surtiera efecto, el test pasaría sin probar nada: se comprueba
        try #require(TimeZone.current.identifier == "Pacific/Honolulu")

        let episode = Episode(id: 1, name: "Pilot", code: "S01E01", airDate: try pilotAirDate)
        let text = try #require(episode.formattedAirDate)
        let shown = try Date.FormatStyle(timeZone: .gmt).day().month(.abbreviated).year().parse(text)
        let components = Calendar(identifier: .gregorian).dateComponents(in: .gmt, from: shown)

        #expect(components.day == 2, "The air date was shown as \(text)")
        #expect(components.month == 12)
        #expect(components.year == 2013)
    }
}
