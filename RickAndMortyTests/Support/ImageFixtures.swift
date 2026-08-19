import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
@testable import RickAndMorty

/// Real images, generated on the fly. Arbitrary bytes won't do: what's under test is
/// ImageIO opening the file and downsampling it, so the fixture must be a PNG ImageIO
/// recognizes. Generating it here instead of committing a binary keeps the project free
/// of resources nobody remembers the origin of, and lets each test pick its own size.
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

/// A byte loader that counts calls and, on request, pauses before answering. Counting
/// proves the cache didn't re-download; pausing lets two requests be in flight at once
/// without depending on the clock.
actor CountingImageLoader {
    private(set) var callCount = 0
    // Whether the download was already cancelled by the time it resumed. Proves
    // cancelling the cell reached the request instead of stopping halfway.
    private(set) var wasCancelled = false

    // Answered in order, the last one repeating: lets a test return broken bytes
    // first and a good image after, like a captive portal that stops intercepting.
    private var responses: [Data]
    private let beforeReturning: (@Sendable () async -> Void)?
    private var remainingFailures: Int
    private let failure: AppError

    init(
        returning data: Data,
        // The first calls fail and it answers fine after that — the shape of a
        // transient failure.
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
        // Counted before pausing: otherwise two calls frozen at once would look
        // like one.
        callCount += 1
        await beforeReturning?()

        // Same as what URLSession does with a cancelled request.
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
