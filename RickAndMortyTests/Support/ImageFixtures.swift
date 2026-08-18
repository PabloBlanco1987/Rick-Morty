import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
@testable import RickAndMorty

// Imágenes de verdad, generadas al vuelo.
// No vale con unos bytes cualesquiera: lo que se está probando es que ImageIO abra el
// fichero y lo reduzca, así que el fixture tiene que ser un PNG que ImageIO reconozca.
// Generarlo aquí en vez de meter un binario en el repo mantiene el proyecto sin
// recursos que nadie sabe de dónde salieron y deja elegir el tamaño en cada test.
enum ImageFixtures {
    enum Failure: Error {
        case couldNotRender
    }

    static func png(side: Int) throws -> Data {
        guard let context = CGContext(
            data: nil,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw Failure.couldNotRender
        }

        context.setFillColor(red: 0.2, green: 0.7, blue: 0.4, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))

        guard let image = context.makeImage() else { throw Failure.couldNotRender }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw Failure.couldNotRender
        }

        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw Failure.couldNotRender }

        return data as Data
    }
}

// Cargador de bytes que cuenta las llamadas y, si se le pide, se para antes de
// contestar. Contar es lo que prueba que la caché no ha vuelto a descargar; pararse es
// lo que permite tener dos peticiones en vuelo a la vez sin depender del reloj.
actor CountingImageLoader {
    private(set) var callCount = 0
    // Si al reanudarse la descarga ya estaba cancelada. Es lo que prueba que cancelar
    // la celda ha llegado hasta la petición y no se ha quedado a medio camino.
    private(set) var wasCancelled = false

    // Se contestan en orden y la última se repite: así un test puede dar unos bytes
    // rotos primero y una imagen buena después, que es lo que hace un portal cautivo
    // que deja de interceptar
    private var responses: [Data]
    private let beforeReturning: (@Sendable () async -> Void)?
    private var remainingFailures: Int
    private let failure: AppError

    init(
        returning data: Data,
        // Las primeras llamadas fallan y a partir de ahí contesta bien, que es la
        // forma de un fallo pasajero
        failingFirst remainingFailures: Int = 0,
        with failure: AppError = .server(statusCode: 503),
        beforeReturning: (@Sendable () async -> Void)? = nil
    ) {
        self.init(
            returningInOrder: [data],
            failingFirst: remainingFailures,
            with: failure,
            beforeReturning: beforeReturning
        )
    }

    init(
        returningInOrder responses: [Data],
        failingFirst remainingFailures: Int = 0,
        with failure: AppError = .server(statusCode: 503),
        beforeReturning: (@Sendable () async -> Void)? = nil
    ) {
        precondition(!responses.isEmpty, "A loader with nothing to return cannot answer anything")
        self.responses = responses
        self.remainingFailures = remainingFailures
        self.failure = failure
        self.beforeReturning = beforeReturning
    }

    func load(_ url: URL) async throws(AppError) -> Data {
        // Se cuenta antes de pararse: si no, dos llamadas congeladas a la vez
        // parecerían una
        callCount += 1
        await beforeReturning?()

        // Lo mismo que hace URLSession con una petición cancelada
        if Task.isCancelled {
            wasCancelled = true
            throw .cancelled
        }

        if remainingFailures > 0 {
            remainingFailures -= 1
            throw failure
        }
        return responses.count > 1 ? responses.removeFirst() : responses[0]
    }
}
