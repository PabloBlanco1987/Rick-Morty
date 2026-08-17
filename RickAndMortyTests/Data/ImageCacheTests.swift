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
            let loader = CountingImageLoader(
                returning: try ImageFixtures.png(side: 600),
                failingFirst: 1,
                with: .server(statusCode: 503)
            )
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
}
