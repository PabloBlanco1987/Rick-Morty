import Foundation
import Testing
@testable import RickAndMorty

// Apoyos que comparten las suites de la caché de imágenes.

// Un directorio propio por test, borrado al salir: si no, un test leería del disco lo
// que ha dejado otro y los aciertos de caché dejarían de significar nada
func withTemporaryDirectory<T>(_ body: (URL) async throws -> T) async throws -> T {
    let directory = URL.temporaryDirectory.appending(
        path: UUID().uuidString,
        directoryHint: .isDirectory
    )
    defer { try? FileManager.default.removeItem(at: directory) }
    return try await body(directory)
}

// La baja del interesado cancelado la da un Task aparte —onCancel es síncrono y está
// fuera del actor—, así que hay que esperar a que llegue. Se cede el turno en vez de
// dormir: no depende del reloj, así que no falla en una máquina lenta.
func waitUntilNothingIsInFlight(in cache: ImageCache) async {
    for _ in 0..<10_000 {
        if await cache.inFlightCount == 0 { return }
        await Task.yield()
    }
    Issue.record("The download was still in flight after its only request was cancelled")
}

// Lo mismo, para saber que una descarga ha llegado a la cola y está esperando hueco
func waitUntilSomethingIsWaiting(in cache: ImageCache) async {
    for _ in 0..<10_000 {
        if await cache.waitingDownloadCount > 0 { return }
        await Task.yield()
    }
    Issue.record("No download ever reached the queue")
}
