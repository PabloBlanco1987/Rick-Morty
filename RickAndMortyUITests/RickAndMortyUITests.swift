import XCTest

// El mismo literal que lee la app al arrancar (LaunchEnvironment.stubbedFlag). Escrito
// una vez para todo el target de UI, para que no aparezca suelto en cada test ni en el
// de arranque.
enum LaunchFlags {
    static let stubbedData = "-stubbed-data"
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
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [LaunchFlags.stubbedData]
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
        XCTAssertTrue(app.staticTexts["Episodes"].exists)
    }

    @MainActor
    func testComingBackFromTheDetailKeepsTheList() throws {
        let app = launchApp()
        // Volver del detalle no puede costar otra carga: el .task de la lista se dispara
        // otra vez al reaparecer, y por eso el view model solo carga si está en idle.
        let cell = app.buttons["character-1"]
        XCTAssertTrue(cell.waitForExistence(timeout: 5))
        cell.tap()
        XCTAssertTrue(app.navigationBars["Rick Sanchez"].waitForExistence(timeout: 5))

        app.navigationBars.buttons.element(boundBy: 0).tap()

        XCTAssertTrue(app.buttons["character-1"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["character-2"].exists)
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
        XCTAssertTrue(app.buttons["Clear search"].exists)
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
}
