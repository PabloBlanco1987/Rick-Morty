import XCTest

// Comprueba que la app arranca y deja una captura de la primera pantalla en el informe.
// Se ejecuta una vez por configuración de la aplicación —idioma, tamaño de letra— que
// tenga el plan de pruebas, que es lo que lo hace útil: la captura enseña si el listado
// se rompe con Dynamic Type sin que nadie tenga que abrir el simulador.
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
        app.launchArguments = ["-stubbed-data"]
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
