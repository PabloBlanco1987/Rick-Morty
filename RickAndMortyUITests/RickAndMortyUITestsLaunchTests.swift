import XCTest

// Comprueba que la app arranca y deja una captura de la primera pantalla en el informe.
// Con runsForEachTargetApplicationUIConfiguration se ejecuta una vez por configuración de
// interfaz: sin plan de pruebas, las cuatro que Xcode trae por defecto —claro y oscuro,
// vertical y horizontal—, así que el informe enseña el listado en las cuatro sin que
// nadie tenga que abrir el simulador. Un plan de pruebas con idiomas o tamaños de letra
// añadiría capturas aquí mismo sin tocar el test.
final class RickAndMortyUITestsLaunchTests: XCTestCase {
    override static var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        // Con datos fijos, igual que el resto de la suite: si no, la captura depende de
        // que la API conteste y de qué conteste
        app.launchArguments = [LaunchFlags.stubbedData]
        app.launch()

        XCTAssertTrue(
            app.buttons["character-1"].waitForExistence(timeout: 10),
            "The app launched but the list never appeared"
        )

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Character list"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
