import CoreGraphics
import Foundation
import Testing
@testable import RickAndMorty

// El precalentamiento de la página siguiente y la pausa durante el fling: las dos piezas
// que hacen que a velocidad de lectura las celdas aparezcan ya con imagen y que un fling
// no gaste cupo en celdas que nadie llega a ver.
@Suite("Image cache warm-up and pause")
struct ImageCacheWarmUpTests {
    private let url = URL(filePath: "/avatars/1.jpeg")
    private let cellSize = CGSize(width: 100, height: 100)
    private let scale: CGFloat = 2

    // MARK: - Precalentamiento

    @Test("Warming a page leaves its images on disk, so the cells find them without a download")
    func warmingLeavesTheBytesOnDisk() async throws {
        try await withTemporaryDirectory { directory in
            // Es la sensación de una app que "ya lo tenía": cuando el usuario baja hasta
            // la página que acaba de llegar, sus celdas salen del disco y no de la red.
            let loader = CountingImageLoader(returning: try ImageFixtures.png(side: 600))
            let sut = ImageCache(directory: directory, settleDelay: .zero, loader: loader.load)
            let urls = [URL(filePath: "/avatars/1.jpeg"), URL(filePath: "/avatars/2.jpeg")]

            await sut.warm(urls)
            let loaded = try await sut.image(for: urls[1], size: cellSize, scale: scale)

            #expect(loaded.origin == .disk)
            #expect(await loader.callCount == 2)
        }
    }

    @Test("Warming what is already on disk costs no download")
    func warmingSkipsWhatIsOnDisk() async throws {
        try await withTemporaryDirectory { directory in
            // Lo que ya está guardado ni se pide: es lo que hace que precalentar una página
            // ya vista —volver atrás y adelante en el scroll— salga gratis
            let loader = CountingImageLoader(returning: try ImageFixtures.png(side: 600))
            let sut = ImageCache(directory: directory, settleDelay: .zero, loader: loader.load)
            _ = try await sut.image(for: url, size: cellSize, scale: scale)

            await sut.warm([url])

            #expect(await loader.callCount == 1)
        }
    }

    @Test("A warm-up does not wait for a cell to settle: there is no cell")
    func warmingDoesNotSettle() async throws {
        try await withTemporaryDirectory { directory in
            // El asentamiento existe para no gastar una petición en una celda que se va.
            // Un precalentamiento no es una celda: con diez segundos de asentamiento, que
            // termine ya solo puede ser porque no ha esperado.
            let loader = CountingImageLoader(returning: try ImageFixtures.png(side: 600))
            let sut = ImageCache(directory: directory, settleDelay: .seconds(10), loader: loader.load)

            let elapsed = await ContinuousClock().measure { await sut.warm([url]) }

            #expect(await loader.callCount == 1)
            #expect(elapsed < .seconds(5))
        }
    }

    @Test("Cancelling a warm-up stops it at the image in flight and asks for no more")
    func cancellingAWarmUpStopsIt() async throws {
        try await withTemporaryDirectory { directory in
            // Cuando llega la página siguiente, la vista cancela el calentamiento de la
            // anterior: lo que estaba en vuelo se cancela y lo que quedaba no se pide.
            let gate = AsyncGate()
            let loader = CountingImageLoader(
                returning: try ImageFixtures.png(side: 600),
                beforeReturning: { await gate.wait() }
            )
            let sut = ImageCache(directory: directory, settleDelay: .zero, loader: loader.load)
            let urls = [URL(filePath: "/avatars/1.jpeg"), URL(filePath: "/avatars/2.jpeg")]

            let warming = Task { await sut.warm(urls) }
            await gate.waitUntilReached()
            warming.cancel()
            // La descarga sigue parada en el pestillo hasta que se abra: primero se
            // comprueba que la baja ha llegado, luego se abre y se deja terminar
            await waitUntilNothingIsInFlight(in: sut)
            await gate.open()
            await warming.value

            #expect(await loader.callCount == 1)
            #expect(await loader.wasCancelled)
        }
    }

    @Test("A visible cell that asks for an image being warmed joins that download")
    func aCellJoinsAWarmUpInFlight() async throws {
        try await withTemporaryDirectory { directory in
            let gate = AsyncGate()
            let loader = CountingImageLoader(
                returning: try ImageFixtures.png(side: 600),
                beforeReturning: { await gate.wait() }
            )
            let sut = ImageCache(directory: directory, settleDelay: .zero, loader: loader.load)

            async let warming: Void = sut.warm([url])
            await gate.waitUntilReached()
            async let cell = sut.image(for: url, size: cellSize, scale: scale)
            await gate.open()

            let loaded = try await cell
            await warming

            #expect(loaded.image.width == 200)
            #expect(await loader.callCount == 1)
        }
    }

    // MARK: - Pausa

    @Test("With the network paused a download waits; resuming lets it through")
    func pausingHoldsTheNetwork() async throws {
        try await withTemporaryDirectory { directory in
            let loader = CountingImageLoader(returning: try ImageFixtures.png(side: 600))
            let sut = ImageCache(directory: directory, settleDelay: .zero, loader: loader.load)

            await sut.setNetworkPaused(true)
            let request = Task { try await sut.image(for: url, size: cellSize, scale: scale) }
            await waitUntilSomethingIsWaiting(in: sut)
            #expect(await loader.callCount == 0)

            await sut.setNetworkPaused(false)
            let loaded = try await request.value

            #expect(loaded.origin == .network)
        }
    }
}
