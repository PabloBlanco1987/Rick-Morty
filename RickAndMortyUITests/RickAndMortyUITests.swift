import XCTest

// El mismo literal que lee la app al arrancar (LaunchEnvironment.stubbedFlag). Escrito
// una vez para todo el target de UI, para que no aparezca suelto en cada test ni en el
// de arranque.
enum LaunchFlags {
    static let stubbedData = "-stubbed-data"
    // Además de lo anterior, un pull to refresh falla (LaunchEnvironment.refreshFailsFlag)
    static let stubbedRefreshFails = "-stubbed-refresh-fails"
    // El tamaño de letra más grande de accesibilidad, para toda la app y sin tocar los
    // ajustes del simulador. Es el argumento que UIKit lee al arrancar.
    static let largestAccessibilityTextSize = [
        "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
    ]
}

// Los recorridos que un usuario hace de verdad, contra la app entera.
//
// Van con datos en memoria, no contra la API: un test de interfaz que dependa de la red
// se pone rojo el día que no hay cobertura, el día que la API contesta 429 —que con
// este proyecto es cualquier día— y el día que alguien añade un personaje. Ninguna de
// esas tres cosas es un fallo de la app, y un test que falla sin que nadie haya roto
// nada acaba ignorándose, que es la peor forma de perder una suite.
//
// Lo que se comprueba aquí es lo que las pruebas unitarias no pueden ver: que las
// piezas están conectadas. El view model se prueba entero en RickAndMortyTests; que
// tocar una celda lleve al detalle correcto, no.
final class RickAndMortyUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // Cada test arranca la app por su cuenta. Es lo que evita guardarla en una propiedad
    // implícitamente desenvuelta que hay que recordar vaciar en el tearDown.
    @MainActor
    private func launchApp(arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [LaunchFlags.stubbedData] + arguments
        app.launch()
        return app
    }

    @MainActor
    func testTheListLoadsAndShowsCharacters() throws {
        let app = launchApp()

        XCTAssertTrue(
            app.buttons["character-1"].waitForExistence(timeout: 5),
            "The first character never made it onto the screen"
        )
        XCTAssertTrue(app.buttons["character-2"].exists)
    }

    @MainActor
    func testTappingACharacterOpensItsDetail() throws {
        let app = launchApp()
        let cell = app.buttons["character-1"]
        XCTAssertTrue(cell.waitForExistence(timeout: 5))

        cell.tap()

        // El nombre del detalle es el de la celda que se tocó: es lo que prueba que la
        // navegación por valor lleva el personaje correcto y no simplemente "un detalle"
        XCTAssertTrue(
            app.navigationBars["Rick Sanchez"].waitForExistence(timeout: 5),
            "The detail did not open for the character that was tapped"
        )
        // Y sus episodios llegan y se pintan: la cabecera "Episodes" también está durante
        // el esqueleto, así que lo que prueba que la carga ha terminado es una fila
        XCTAssertTrue(app.staticTexts["Episodes"].exists)
        XCTAssertTrue(app.staticTexts["Episode 1"].waitForExistence(timeout: 5), "The episode list never loaded")
        XCTAssertTrue(app.staticTexts["S01E01"].exists)
    }

    @MainActor
    func testScrollingToTheEndLoadsTheNextPage() throws {
        // El stub tiene veinticinco personajes y pagina de veinte en veinte: los últimos
        // cinco solo existen si al acercarse al final se ha pedido la segunda página. Es
        // el scroll infinito de punta a punta: la celda aparece, el view model pide, la
        // rejilla crece.
        let app = launchApp()
        XCTAssertTrue(app.buttons["character-1"].waitForExistence(timeout: 5))

        scroll(app, untilExists: app.buttons["character-25"])

        XCTAssertTrue(app.buttons["character-25"].exists, "The second page never made it onto the screen")
    }

    @MainActor
    func testComingBackFromTheDetailKeepsTheList() throws {
        // Volver del detalle no puede costar otra carga: el .task de la lista se dispara
        // otra vez al reaparecer, y por eso el view model solo carga si está en idle. Se
        // baja hasta la segunda página antes de entrar porque es lo que hace la prueba
        // observable: si al volver se recargara, la lista volvería a la primera página y
        // el personaje 21 —que solo existe en la segunda— habría desaparecido.
        let app = launchApp()
        XCTAssertTrue(app.buttons["character-1"].waitForExistence(timeout: 5))
        let cell = app.buttons["character-21"]
        scroll(app, untilExists: cell)
        cell.tap()
        XCTAssertTrue(app.navigationBars["Supernova"].waitForExistence(timeout: 5))

        app.navigationBars.buttons.element(boundBy: 0).tap()

        XCTAssertTrue(
            app.buttons["character-21"].waitForExistence(timeout: 5),
            "Coming back from the detail lost the page the user had scrolled to"
        )
    }

    @MainActor
    func testSearchingNarrowsTheListAndClearingBringsItBack() throws {
        let app = launchApp()
        XCTAssertTrue(app.buttons["character-1"].waitForExistence(timeout: 5))

        let searchField = app.searchFields.firstMatch
        searchField.tap()
        searchField.typeText("Summer")

        // Summer Smith es el personaje 3: al buscar tiene que quedarse él y desaparecer
        // los demás
        XCTAssertTrue(app.buttons["character-3"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["character-1"].exists)

        searchField.buttons.element(boundBy: 0).tap()

        XCTAssertTrue(app.buttons["character-1"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testASearchWithNoMatchesShowsTheEmptyStateAndNotAnError() throws {
        let app = launchApp()
        XCTAssertTrue(app.buttons["character-1"].waitForExistence(timeout: 5))

        let searchField = app.searchFields.firstMatch
        searchField.tap()
        searchField.typeText("zzzzzzzz")

        // Sin resultados no es un fallo: la pantalla que sale ofrece quitar lo que se
        // buscó, no reintentar. Y dice "búsqueda", no "filtros": no se ha tocado ninguno
        XCTAssertTrue(app.staticTexts["No matches"].waitForExistence(timeout: 5))
        let clear = app.buttons["Clear search"]
        XCTAssertTrue(clear.exists)

        // Y ese botón devuelve la lista entera
        clear.tap()
        XCTAssertTrue(app.buttons["character-1"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testFilteringByStatusChangesTheList() throws {
        let app = launchApp()
        XCTAssertTrue(app.buttons["character-1"].waitForExistence(timeout: 5))

        app.navigationBars.buttons["Filters"].tap()
        let statusPicker = app.buttons["filter-status"]
        XCTAssertTrue(statusPicker.waitForExistence(timeout: 5))
        statusPicker.tap()
        app.buttons["Dead"].tap()
        app.buttons["Done"].tap()

        // Rick está vivo, así que con el filtro puesto no puede seguir en la lista;
        // Bird Person, que es el 7, sí
        XCTAssertTrue(app.buttons["character-7"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["character-1"].exists)
    }

    @MainActor
    func testClearingTheFiltersBringsTheWholeListBack() throws {
        let app = launchApp()
        XCTAssertTrue(app.buttons["character-1"].waitForExistence(timeout: 5))

        // Sin nada puesto, "Clear" no hace nada y no se puede tocar
        app.navigationBars.buttons["Filters"].tap()
        let clear = app.buttons["Clear"]
        XCTAssertTrue(clear.waitForExistence(timeout: 5))
        XCTAssertFalse(clear.isEnabled, "Clear must be disabled while no filter is active")

        // Con un filtro puesto se enciende, y al tocarlo la lista vuelve entera
        app.buttons["filter-status"].tap()
        app.buttons["Dead"].tap()
        XCTAssertTrue(clear.isEnabled)
        clear.tap()
        app.buttons["Done"].tap()

        XCTAssertTrue(app.buttons["character-1"].waitForExistence(timeout: 5))
    }

    // MARK: - Dynamic Type

    // Las tres pantallas con el tamaño de letra más grande que existe. Lo que se
    // comprueba es que a ese tamaño todo sigue en pantalla y se puede tocar: la celda,
    // el detalle al que lleva y los selectores de la hoja de filtros.
    @MainActor
    func testTheScreensStayUsableAtTheLargestTextSize() throws {
        let app = launchApp(arguments: LaunchFlags.largestAccessibilityTextSize)

        let cell = app.buttons["character-1"]
        XCTAssertTrue(cell.waitForExistence(timeout: 5))
        XCTAssertTrue(cell.isHittable, "At the largest text size the first cell must still be reachable")

        cell.tap()
        XCTAssertTrue(app.navigationBars["Rick Sanchez"].waitForExistence(timeout: 5))

        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["character-1"].waitForExistence(timeout: 5))
        app.navigationBars.buttons["Filters"].tap()
        let statusPicker = app.buttons["filter-status"]
        XCTAssertTrue(statusPicker.waitForExistence(timeout: 5))
        XCTAssertTrue(statusPicker.isHittable)
    }

    // MARK: - Refresco fallido

    @MainActor
    func testAFailedRefreshKeepsTheListAndShowsANoticeThatCanBeDismissed() throws {
        let app = launchApp(arguments: [LaunchFlags.stubbedRefreshFails])
        let cell = app.buttons["character-1"]
        XCTAssertTrue(cell.waitForExistence(timeout: 5))

        // Tirar de la lista hacia abajo, como haría el usuario
        let start = cell.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
        let end = start.withOffset(CGVector(dx: 0, dy: 500))
        start.press(forDuration: 0.2, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.5)

        // El aviso aparece, dice qué ha pasado y qué significa, y la lista sigue ahí
        let notice = app.buttons["refresh-failed"]
        XCTAssertTrue(notice.waitForExistence(timeout: 5), "The refresh failure notice never appeared")
        XCTAssertTrue(notice.label.contains("No connection"))
        XCTAssertTrue(notice.label.contains("out of date"))
        XCTAssertTrue(app.buttons["character-1"].exists, "A failed refresh must not take the list away")

        // Y se descarta tocándolo
        notice.tap()
        XCTAssertTrue(notice.waitForNonExistence(timeout: 3))
    }

    // MARK: - Helpers

    // Baja por la rejilla hasta que la celda pedida exista, con un tope: la rejilla es
    // perezosa, así que una celda que aún no se ha creado no existe para XCTest, y la
    // única forma de llegar a ella es hacer scroll como lo haría el usuario. Con veinte
    // celdas por página y dos por fila, ocho pantallas sobran.
    @MainActor
    private func scroll(_ app: XCUIApplication, untilExists element: XCUIElement, maxSwipes: Int = 8) {
        for _ in 0..<maxSwipes {
            // Un respiro entre gesto y gesto, para que una página que se acabe de pedir
            // llegue a pintarse antes de dar el siguiente
            if element.waitForExistence(timeout: 1) { return }
            app.swipeUp()
        }
        _ = element.waitForExistence(timeout: 5)
    }
}
