import CoreGraphics
import Foundation
import Testing
@testable import RickAndMorty

extension RetryPolicy {
    // Reintenta sin esperar: en un test lo que importa es que lo vuelva a intentar, no
    // cuánto duerme, y así la suite se queda en milisegundos
    static let immediate = RetryPolicy(maxAttempts: 3, baseDelay: .zero, rateLimitedDelay: .zero)
}

@Suite("Image cache")
struct ImageCacheTests {
    private let url = URL(filePath: "/avatars/1.jpeg")
    // Una celda de 100 pt en una pantalla 2x son 200 px: el fixture tiene 600, así que
    // si la reducción no ocurre se nota en el ancho de la imagen que sale
    private let cellSize = CGSize(width: 100, height: 100)
    private let scale: CGFloat = 2

    @Test("The image is decoded at the size of the cell, not at the size of the file")
    func downsamplesToTheCellSize() async throws {
        try await withTemporaryDirectory { directory in
            let loader = CountingImageLoader(returning: try ImageFixtures.png(side: 600))
            let sut = ImageCache(directory: directory, settleDelay: .zero, loader: loader.load)

            let loaded = try await sut.image(for: url, size: cellSize, scale: scale)

            #expect(loaded.image.width == 200)
            #expect(loaded.image.height == 200)
        }
    }

    @Test("The same URL at the same size comes back from memory the second time")
    func servesTheSecondRequestFromMemory() async throws {
        try await withTemporaryDirectory { directory in
            let loader = CountingImageLoader(returning: try ImageFixtures.png(side: 600))
            let sut = ImageCache(directory: directory, settleDelay: .zero, loader: loader.load)

            let first = try await sut.image(for: url, size: cellSize, scale: scale)
            let second = try await sut.image(for: url, size: cellSize, scale: scale)

            #expect(first.origin == .network)
            #expect(second.origin == .memory)
            #expect(await loader.callCount == 1)
        }
    }

    @Test("A cache that starts with an empty memory finds the bytes on disk")
    func servesFromDiskWithAColdMemory() async throws {
        try await withTemporaryDirectory { directory in
            // Dos instancias sobre el mismo directorio: es lo que pasa entre dos
            // arranques de la app, con la memoria vacía y el disco puesto.
            let loader = CountingImageLoader(returning: try ImageFixtures.png(side: 600))
            let first = ImageCache(directory: directory, settleDelay: .zero, loader: loader.load)
            _ = try await first.image(for: url, size: cellSize, scale: scale)

            let second = ImageCache(directory: directory, settleDelay: .zero, loader: loader.load)
            let loaded = try await second.image(for: url, size: cellSize, scale: scale)

            #expect(loaded.origin == .disk)
            #expect(await loader.callCount == 1)
        }
    }

    @Test("Two concurrent requests for the same URL only trigger one download")
    func deduplicatesConcurrentRequests() async throws {
        try await withTemporaryDirectory { directory in
            // El pestillo congela la primera descarga dentro del cargador, así que la
            // segunda petición llega con la primera todavía en vuelo. Sin él habría
            // que dormir y confiar, que es como se escriben los tests que fallan una
            // vez de cada treinta.
            let gate = AsyncGate()
            let loader = CountingImageLoader(
                returning: try ImageFixtures.png(side: 600),
                beforeReturning: { await gate.wait() }
            )
            let sut = ImageCache(directory: directory, settleDelay: .zero, loader: loader.load)

            async let first = sut.image(for: url, size: cellSize, scale: scale)
            await gate.waitUntilReached()
            async let second = sut.image(for: url, size: cellSize, scale: scale)
            await gate.open()

            let images = try await [first, second]

            #expect(await loader.callCount == 1)
            #expect(images.allSatisfy { $0.image.width == 200 })
        }
    }

    @Test("A download nobody is waiting for any more is cancelled, not left in the queue")
    func cancelsDownloadsNobodyIsWaitingFor() async throws {
        try await withTemporaryDirectory { directory in
            // Es la diferencia entre un scroll rápido que se rellena y uno que deja el
            // grid en gris: URLSession abre seis conexiones por host, así que una
            // petición que ya no le importa a nadie no es gratis, le está quitando el
            // turno a una celda que sí se ve.
            let gate = AsyncGate()
            let loader = CountingImageLoader(
                returning: try ImageFixtures.png(side: 600),
                beforeReturning: { await gate.wait() }
            )
            let sut = ImageCache(directory: directory, settleDelay: .zero, loader: loader.load)

            let request = Task { try await sut.image(for: url, size: cellSize, scale: scale) }
            await gate.waitUntilReached()
            request.cancel()
            await waitUntilNothingIsInFlight(in: sut)

            await gate.open()
            _ = try? await request.value

            #expect(await loader.wasCancelled)
        }
    }

    @Test("A cell the user scrolled straight past never costs a request")
    func doesNotSpendARequestOnACellThatWentBy() async throws {
        try await withTemporaryDirectory { directory in
            // En un vistazo rápido las celdas asoman y se van en decenas de
            // milisegundos. Pedir esas imágenes no solo es tirar ancho de banda: es la
            // ráfaga que hace que la API conteste 429 y se lleve por delante también la
            // carga de la página siguiente.
            let loader = CountingImageLoader(returning: try ImageFixtures.png(side: 600))
            let sut = ImageCache(
                directory: directory,
                settleDelay: .milliseconds(200),
                loader: loader.load
            )

            let request = Task { try await sut.image(for: url, size: cellSize, scale: scale) }
            // La celda se va antes de que le dé tiempo a asentarse
            request.cancel()
            _ = try? await request.value

            #expect(await loader.callCount == 0)
        }
    }

    @Test("A cell that stays on screen gets its image once it has settled")
    func aCellThatStaysIsRequestedAfterSettling() async throws {
        try await withTemporaryDirectory { directory in
            // La otra cara de la anterior: la espera existe para no gastar peticiones en
            // celdas que se van, no para retrasar a las que se quedan. Se mide que la
            // espera exista y que después la petición salga; una máquina lenta solo puede
            // alargarla.
            let loader = CountingImageLoader(returning: try ImageFixtures.png(side: 600))
            let sut = ImageCache(directory: directory, settleDelay: .milliseconds(50), loader: loader.load)

            let elapsed = try await ContinuousClock().measure {
                _ = try await sut.image(for: url, size: cellSize, scale: scale)
            }

            #expect(elapsed >= .milliseconds(40))
            #expect(await loader.callCount == 1)
        }
    }

    @Test("The same URL at two sizes gives two bitmaps out of a single download")
    func reusesTheBytesAcrossSizes() async throws {
        try await withTemporaryDirectory { directory in
            // Los bytes se guardan sin reducir precisamente para esto: otro tamaño
            // cuesta una decodificación, no otra descarga.
            let loader = CountingImageLoader(returning: try ImageFixtures.png(side: 600))
            let sut = ImageCache(directory: directory, settleDelay: .zero, loader: loader.load)

            let small = try await sut.image(for: url, size: cellSize, scale: scale)
            let large = try await sut.image(for: url, size: CGSize(width: 300, height: 300), scale: scale)

            #expect(small.image.width == 200)
            #expect(large.image.width == 600)
            #expect(await loader.callCount == 1)
        }
    }

    @Test("Bytes that are not an image are a decoding failure, not a crash")
    func rejectsBytesThatAreNotAnImage() async throws {
        try await withTemporaryDirectory { directory in
            let loader = CountingImageLoader(returning: Data("not an image".utf8))
            let sut = ImageCache(directory: directory, settleDelay: .zero, loader: loader.load)

            await #expect(throws: AppError.decoding) {
                _ = try await sut.image(for: url, size: cellSize, scale: scale)
            }
        }
    }

    @Test("A download that fails with something worth retrying is retried")
    func retriesWhatIsWorthRetrying() async throws {
        try await withTemporaryDirectory { directory in
            // Sin el reintento, un 503 pasajero deja esa celda en gris hasta que el
            // usuario la saque de la pantalla y la vuelva a meter: es lo único que
            // hace que su .task se dispare otra vez.
            // Con el fallo por defecto del cargador, un 503: el tropiezo pasajero de libro
            let loader = CountingImageLoader(returning: try ImageFixtures.png(side: 600), failingFirst: 1)
            // Sin espera entre intentos: lo que se prueba es que reintente, no cuánto
            // duerme, y la suite se queda en milisegundos
            let sut = ImageCache(
                directory: directory,
                settleDelay: .zero,
                loader: ImageCache.retrying(loader.load, policy: .immediate)
            )

            let loaded = try await sut.image(for: url, size: cellSize, scale: scale)

            #expect(loaded.image.width == 200)
            #expect(await loader.callCount == 2)
        }
    }

    @Test("A download that fails with something not worth retrying is not retried")
    func doesNotRetryWhatIsNotWorthRetrying() async throws {
        try await withTemporaryDirectory { directory in
            let loader = CountingImageLoader(
                returning: try ImageFixtures.png(side: 600),
                failingFirst: 5,
                with: .notFound
            )
            let sut = ImageCache(
                directory: directory,
                settleDelay: .zero,
                loader: ImageCache.retrying(loader.load, policy: .immediate)
            )

            await #expect(throws: AppError.notFound) {
                _ = try await sut.image(for: url, size: cellSize, scale: scale)
            }
            #expect(await loader.callCount == 1)
        }
    }

    @Test("A download that fails surfaces the error it failed with")
    func propagatesTheDownloadFailure() async throws {
        try await withTemporaryDirectory { directory in
            let sut = ImageCache(directory: directory, settleDelay: .zero) { _ throws(AppError) in throw .offline }

            await #expect(throws: AppError.offline) {
                _ = try await sut.image(for: url, size: cellSize, scale: scale)
            }
        }
    }

    @Test("Being rate limited is not retried here: the shared limiter owns that")
    func doesNotRetryRateLimiting() async throws {
        try await withTemporaryDirectory { directory in
            // El 429 es retryable para el cliente HTTP, pero reintentarlo por imagen sería
            // que cada una de las cuatro descargas en vuelo repitiera por su cuenta la
            // ráfaga que nos ganó el límite. De él se encarga el freno compartido de
            // RateLimiter, una vez para todas.
            let loader = CountingImageLoader(
                returning: try ImageFixtures.png(side: 600),
                failingFirst: 5,
                with: .rateLimited
            )
            let sut = ImageCache(
                directory: directory,
                settleDelay: .zero,
                loader: ImageCache.retrying(loader.load, policy: .immediate)
            )

            await #expect(throws: AppError.rateLimited) {
                _ = try await sut.image(for: url, size: cellSize, scale: scale)
            }
            #expect(await loader.callCount == 1)
        }
    }

    @Test("Bytes that do not decode are not kept: the next attempt goes back to the network")
    func doesNotKeepBytesThatDoNotDecode() async throws {
        try await withTemporaryDirectory { directory in
            // Es lo que hace un portal cautivo: el wifi de un hotel contesta 200 con su
            // página de acceso. La descarga guarda los bytes antes de saber si decodifican,
            // y si se quedaran en disco, cada visita siguiente los leería de ahí, fallaría
            // igual y no volvería a bajar la imagen nunca.
            let loader = CountingImageLoader(returningInOrder: [
                Data("<html>hotel wifi login</html>".utf8),
                try ImageFixtures.png(side: 600),
            ])
            let sut = ImageCache(directory: directory, settleDelay: .zero, loader: loader.load)

            await #expect(throws: AppError.decoding) {
                _ = try await sut.image(for: url, size: cellSize, scale: scale)
            }
            let loaded = try await sut.image(for: url, size: cellSize, scale: scale)

            // De la red y no del disco: los bytes rotos se han borrado
            #expect(loaded.origin == .network)
            #expect(loaded.image.width == 200)
            #expect(await loader.callCount == 2)
        }
    }

    @Test("Cancelling one of two cells sharing a download leaves the other's download running")
    func cancellingOneWaiterKeepsTheDownloadForTheOther() async throws {
        try await withTemporaryDirectory { directory in
            // Es la razón de llevar la cuenta de interesados y no una bandera: la
            // descarga se cancela solo cuando se va el último. Si se cancelara con el
            // primero, una celda que sale de pantalla dejaría sin imagen a la vecina que
            // sigue mirándola.
            let gate = AsyncGate()
            let loader = CountingImageLoader(
                returning: try ImageFixtures.png(side: 600),
                beforeReturning: { await gate.wait() }
            )
            let sut = ImageCache(directory: directory, settleDelay: .zero, loader: loader.load)

            let first = Task { try await sut.image(for: url, size: cellSize, scale: scale) }
            await gate.waitUntilReached()
            let second = Task { try await sut.image(for: url, size: cellSize, scale: scale) }
            await waitUntil(2, areWaitingFor: url, in: sut)

            first.cancel()
            await waitUntil(1, areWaitingFor: url, in: sut)
            await gate.open()

            let loaded = try await second.value
            #expect(loaded.image.width == 200)
            #expect(await loader.callCount == 1)
            #expect(await loader.wasCancelled == false)
            await #expect(throws: AppError.cancelled) { _ = try await first.value }
        }
    }
}
