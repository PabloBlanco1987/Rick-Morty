import CoreGraphics
import CryptoKit
import Foundation
import ImageIO

/// A two-level image cache with download deduplication. The three costs that break a
/// scroll, by impact:
/// 1. Decoding. An avatar is ~25 KB compressed at 300x300 px, but the decoded bitmap
///    runs 360 KB — multiplied across on-screen cells, that's what triggers a memory
///    warning. Decoded here at cell size, on the spot, not at paint time: the bitmap
///    is never bigger than what's shown, so layout sets the ceiling, not the server.
///    Forcing decode off the main thread is what actually matters per cell.
/// 2. Repeated work. Scrolling back can't cost another download or decode: memory
///    first, disk second, network as a last resort.
/// 3. Asking for the same thing twice at once. Normal in a grid, not an edge case —
///    two requests for the same URL would be two connections and two decodes for the
///    same bitmap.
///
/// An actor, not a class with locks, because the state it guards — the in-flight
/// downloads dictionary — is touched by as many tasks as there are cells on screen,
/// and isolation handles that without a single hand-rolled lock.
actor ImageCache {
    // Where the image came from. Returned because the view needs it to decide whether
    // to fade in: what was already in memory has to appear instantly.
    enum Origin: Sendable {
        case memory
        case disk
        case network
    }

    struct LoadedImage: Sendable {
        let image: CGImage
        let origin: Origin
    }

    // Injected so tests don't touch the network. Production uses Self.download.
    typealias DataLoader = @Sendable (URL) async throws(AppError) -> Data

    static let shared = ImageCache()

    private let directory: URL
    private let loader: DataLoader
    private let settleDelay: Duration
    private let memory = NSCache<NSString, Entry>()

    // Everything headed to the network passes through here: few at once, last
    // requested first — what paints what's on screen instead of the queue of what's
    // already been scrolled past.
    private let queue: DownloadQueue

    // In-flight downloads, by URL. If two cells ask for the same image at once, the
    // second finds the first's task here and waits on it instead of opening another
    // connection. Keyed by URL alone, not URL plus size, on purpose: it's the download
    // that can't be duplicated, and the downloaded bytes serve any size.
    private var inFlight: [URL: Download] = [:]
    private var lastWaiterToken = 0

    // internal so tests can check that a download nobody wants anymore truly
    // disappears, that a pause truly holds, and that a second cell joined a download
    // before the first was cancelled
    var inFlightCount: Int { inFlight.count }
    var waitingDownloadCount: Int {
        get async { await queue.waitingCount }
    }
    func waiterCount(for url: URL) -> Int { inFlight[url]?.waiters.count ?? 0 }

    init(
        directory: URL = ImageCache.defaultDirectory,
        // 50 MB of bitmaps. Today's decoded avatar is 360 KB, so that's room for
        // ~145 — more than four screens of scroll, which is about how far back a
        // user tends to go.
        memoryLimit: Int = 50 * 1024 * 1024,
        // Four at once. More wouldn't arrive sooner — the bottleneck is connections
        // and bandwidth, not how many requests were fired — and would leave the
        // server eating bursts that turn into 5xx, which then takes down the next
        // page's request too.
        maxConcurrentDownloads: Int = 4,
        // How long a cell has to sit on screen before it costs a request. In a quick
        // glance cells appear and vanish in tens of milliseconds; requesting those
        // images burns requests on what nobody saw, and that kind of burst is what
        // earns a 429 that also takes down the next page's load. Doesn't delay
        // anything already in memory or on disk — that never reaches this at all.
        settleDelay: Duration = .milliseconds(120),
        // Injected so tests don't touch the network; without it, the real download
        // with retries. An optional, not a default value, so the production one —
        // two static members composed together — reads here, not in the signature.
        loader: DataLoader? = nil
    ) {
        self.directory = directory
        self.loader = loader ?? Self.retrying(Self.download)
        self.settleDelay = settleDelay
        self.queue = DownloadQueue(limit: maxConcurrentDownloads)
        // NSCache already empties itself under memory pressure, so this limit is a
        // ceiling, not the only defense.
        memory.totalCostLimit = memoryLimit
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    // Returns the image already decoded at the size it'll be painted. size is in
    // points, scale is the screen's; converted to pixels here, not in the view,
    // because size is part of the memory key — the same URL at 110pt and 300pt are
    // two different bitmaps.
    func image(for url: URL, size: CGSize, scale: CGFloat) async throws(AppError) -> LoadedImage {
        let pixelSize = Self.pixelSize(for: size, scale: scale)
        let key = Self.memoryKey(url: url, pixelSize: pixelSize)

        if let entry = memory.object(forKey: key) {
            return LoadedImage(image: entry.image, origin: .memory)
        }

        let fetched = try await fetch(url, priority: .visible)

        // Before decoding, the expensive part — if the cell has already scrolled off,
        // there's no point spending CPU and memory on a bitmap nobody will see. The
        // bytes are already on disk, so the work that did matter isn't lost.
        if Task.isCancelled { throw .cancelled }

        guard let image = await Self.downsample(fetched.data, to: pixelSize) else {
            // Bytes that aren't an image can't stay on disk: the download saves them
            // before knowing if they decode, and if left there every future visit
            // would read the same broken bytes, fail the same way, and never
            // re-download. This is what a captive portal does — a hotel wifi
            // answering 200 with its login page — and left alone it poisons the
            // cache until the system evicts it. Deleting sends the next attempt back
            // to the network.
            await Self.removeFile(at: fileURL(for: url))
            throw .decoding
        }

        memory.setObject(Entry(image), forKey: key, cost: image.decodedByteCount)
        return LoadedImage(image: image, origin: fetched.origin)
    }

    // Saves to disk the images of a page that just arrived and isn't visible yet, so
    // when the user scrolls down to it the cells already have their image instead of
    // a gap filling in — the feeling of an app that "already had it."
    //
    // Sequential on purpose: takes at most one of the four slots and spends the
    // server's quota one at a time, so it never competes with what's on screen. Goes
    // through the same `fetch` as cells, at low priority: a visible cell requesting an
    // image already warming joins that download, and if nobody else was waiting,
    // cancelling the warm cancels the download with it.
    //
    // Known limit: a visible cell that joins a warm still waiting at the back of the
    // queue waits behind the visible cells already queued ahead of it. Since warming
    // is sequential, that's at most one round of four downloads, and doesn't justify a
    // priority promotion for it.
    func warm(_ urls: [URL]) async {
        for url in urls {
            guard !Task.isCancelled else { return }
            // What's already on disk doesn't even need the task — a stat is cheaper
            // than building the download just to find out it wasn't needed.
            guard !FileManager.default.fileExists(atPath: fileURL(for: url).path()) else { continue }
            _ = try? await fetch(url, priority: .prefetch)
        }
    }

    // The view sets this while the scroll is flinging and clears it on stop: during a
    // fling, every request that goes out is quota spent on a cell that's gone by the
    // time it lands. What's in memory or on disk skips the queue and keeps appearing;
    // only the network exit is held back.
    func setNetworkPaused(_ paused: Bool) async {
        await queue.setPaused(paused)
    }

    // MARK: - Bytes

    private struct Fetched: Sendable {
        let data: Data
        let origin: Origin
    }

    // The download and who's waiting on it. Counting waiters isn't extra bookkeeping —
    // it's what enables cancellation. Without it, a fast scroll leaves hundreds of live
    // requests for cells no longer on screen, and since URLSession opens six
    // connections per host, the cells still visible wait behind images nobody will
    // ever look at. The symptom is a grid full of gray gaps that never fill in.
    private struct Download {
        let task: Task<Fetched, any Error>
        // A set of tokens, not a counter: removing a token that's already gone is a
        // no-op, so it doesn't matter whether it leaves via the normal path or
        // cancellation.
        var waiters: Set<Int>
    }

    private func fetch(_ url: URL, priority: DownloadQueue.Priority) async throws(AppError) -> Fetched {
        let (task, token) = joinDownload(for: url, priority: priority)
        defer { leaveDownload(for: url, token: token, cancelled: false) }

        do {
            // withTaskCancellationHandler is what makes cancelling the cell cancel
            // the download: without it, cancelling a waiter doesn't cancel what it's
            // waiting on, and Task.value wouldn't even throw — the request would keep
            // sitting in the queue.
            return try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                // onCancel is synchronous and outside the actor, so leaving happens
                // in a separate hop.
                Task { await self.leaveDownload(for: url, token: token, cancelled: true) }
            }
        } catch let error as AppError {
            throw error
        } catch is CancellationError {
            throw .cancelled
        } catch {
            throw .unknown
        }
    }

    // Priority is whoever opens the download's. If it was already in flight, whoever
    // arrives just joins it — it's the request itself that can't be duplicated.
    private func joinDownload(
        for url: URL,
        priority: DownloadQueue.Priority
    ) -> (task: Task<Fetched, any Error>, token: Int) {
        lastWaiterToken += 1
        let token = lastWaiterToken

        if var download = inFlight[url] {
            download.waiters.insert(token)
            inFlight[url] = download
            return (download.task, token)
        }

        let file = fileURL(for: url)
        let loader = self.loader
        let queue = self.queue
        let settleDelay = self.settleDelay
        let task = Task<Fetched, any Error> {
            // Disk before network. Reading a local file costs microseconds; a request
            // costs tens of milliseconds even when it ends in a 304.
            if let stored = await Self.readFile(at: file) {
                return Fetched(data: stored, origin: .disk)
            }

            // The cell has to settle before it costs a request. If the user's already
            // scrolled past, this task will be cancelled by the time the wait ends and
            // nothing gets requested. A prefetch isn't a cell that can leave, so it has
            // nothing to settle.
            if priority == .visible {
                try await Task.sleep(for: settleDelay)
            }
            // The slot is only requested for the network trip — a disk hit doesn't
            // compete for connections and shouldn't wait on anyone. The closure's full
            // signature is spelled out because typed-throws inference inside a literal
            // falls back to `any Error`.
            let data = try await queue.enqueue(priority: priority) { () async throws(AppError) -> Data in
                try await loader(url)
            }
            // Saves the original bytes, not the downsampled bitmap: if the same image
            // is needed at another size tomorrow — a wider cell, the detail screen —
            // it comes from disk instead of the network.
            await Self.writeFile(data, to: file)
            return Fetched(data: data, origin: .network)
        }

        inFlight[url] = Download(task: task, waiters: [token])
        return (task, token)
    }

    // If the one leaving was the last, and leaves because it was cancelled, the
    // download cancels with it: nobody's going to see that image, and the connection
    // is needed for the cells still on screen.
    private func leaveDownload(for url: URL, token: Int, cancelled: Bool) {
        guard var download = inFlight[url], download.waiters.remove(token) != nil else { return }

        guard download.waiters.isEmpty else {
            inFlight[url] = download
            return
        }

        inFlight[url] = nil
        if cancelled { download.task.cancel() }
    }

    // @concurrent because the project builds with SWIFT_APPROACHABLE_CONCURRENCY:
    // without it a nonisolated async function runs on the caller's executor — the
    // actor itself here — and a disk read would queue up every other cell behind it.
    // With it, the work goes to the global pool and the actor stays free.
    @concurrent
    private static func readFile(at url: URL) async -> Data? {
        // .mappedIfSafe: the file is mapped instead of copied to the heap, and ImageIO
        // reads straight from there.
        try? Data(contentsOf: url, options: .mappedIfSafe)
    }

    @concurrent
    private static func writeFile(_ data: Data, to url: URL) async {
        // If writing fails — disk full, or the system emptied Caches/ underneath —
        // that's no reason not to show the image: only next time's disk hit is lost.
        try? data.write(to: url, options: .atomic)
    }

    @concurrent
    private static func removeFile(at url: URL) async {
        // Not there means already done.
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Decoding

    @concurrent
    private static func downsample(_ data: Data, to pixelSize: CGSize) async -> CGImage? {
        // kCGImageSourceShouldCache: false so ImageIO doesn't also keep the
        // full-size image around while building the thumbnail — exactly what this
        // is meant to avoid.
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            return nil
        }

        let maxPixelSize = Int(max(pixelSize.width, pixelSize.height).rounded(.up))
        let options = [
            // Builds a thumbnail even when the file has no embedded one, which is
            // the case for this API's avatars.
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            // Applies EXIF orientation while downsampling, so the result is already
            // upright.
            kCGImageSourceCreateThumbnailWithTransform: true,
            // Forces decoding right here, right now. Without this ImageIO defers to
            // paint time, which lands on the main thread mid-scroll — the difference
            // between smooth and a hitch per cell.
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ] as [CFString: Any] as CFDictionary

        return CGImageSourceCreateThumbnailAtIndex(source, 0, options)
    }

    // MARK: - Keys

    // NSCache only stores objects, so the image travels wrapped in a class — nothing
    // more; cost is computed elsewhere, on insert.
    private final class Entry {
        let image: CGImage
        init(_ image: CGImage) { self.image = image }
    }

    private static func pixelSize(for size: CGSize, scale: CGFloat) -> CGSize {
        CGSize(width: (size.width * scale).rounded(.up), height: (size.height * scale).rounded(.up))
    }

    private static func memoryKey(url: URL, pixelSize: CGSize) -> NSString {
        "\(url.absoluteString)|\(Int(pixelSize.width))x\(Int(pixelSize.height))" as NSString
    }

    private func fileURL(for url: URL) -> URL {
        // SHA-256 of the URL: a fixed-length name, no characters the filesystem
        // would reject, and never over 255 bytes per component — which is what
        // percent-encoding a long URL would risk.
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return directory.appending(path: name, directoryHint: .notDirectory)
    }

    // Caches/, not Documents/: these bytes can always be re-downloaded, so they
    // shouldn't be backed up to iCloud, and the system is free to reclaim them under
    // storage pressure.
    // TODO: [Out of scope · README §8] Disk cache pruning.
    /*
     Reason: the directory grows unbounded today, emptied only when the system needs
     the space. Left this way on purpose — the API's 826 avatars are ~20 MB worst case
     (fits entirely), and a rushed LRU prune risks deleting exactly what's in use.
     Ready to plug in: would come in as a `trim(to:)` on this actor, called on entering
     the background, sorting files by `.contentAccessDateKey` and deleting the oldest
     until under the limit. Reads and writes wouldn't change — both already go through
     `fileURL(for:)`.
     */
    private static var defaultDirectory: URL {
        URL.cachesDirectory.appending(path: "ImageCache", directoryHint: .isDirectory)
    }

    // MARK: - Download

    // Retrying is added by composing, the same way RetryingHTTPClient wraps the HTTP
    // client: the download doesn't know it's being retried, and the retry doesn't
    // know where the bytes come from.
    //
    // This is the short retry: one request's stumble — a passing 502, a timeout —
    // repeats here within hundreds of milliseconds, and since the download is
    // deduplicated, it repeats once for every cell waiting on it. The longer,
    // multi-second bad stretch is covered by CachedAsyncImage as long as the cell
    // stays on screen — the two layers split the time instead of overlapping.
    static func retrying(
        _ loader: @escaping DataLoader,
        policy: RetryPolicy = .default
    ) -> DataLoader {
        // Signatures spelled out in full because typed-throws inference inside a
        // closure literal falls back to `any Error`.
        { (url: URL) async throws(AppError) -> Data in
            // 429 is excluded on purpose — the difference between climbing out of the
            // hole and digging it deeper. RateLimiter's shared brake handles that;
            // retrying it here would mean every in-flight image repeating on its own
            // the burst that earned the limit in the first place.
            try await policy.attempt(
                shouldRetry: { $0.isRetryable && $0 != .rateLimited },
                { () async throws(AppError) -> Data in try await loader(url) }
            )
        }
    }

    // A direct download, bypassing HTTPClient: that path decodes JSON, this one just
    // needs raw bytes. Everything else — limiter token, logging, transport, status
    // code — is the same URLSession.perform the HTTP client uses, written once for
    // both. And the limiter is the same object as the HTTP client's: one server quota
    // for JSON and images means one shared brake.
    //
    // Only what actually goes out to the network is logged and spends a token — what
    // resolves from memory or disk never reaches here, so the log says what's being
    // requested out, not how many cells got painted. Called from inside the queue, so
    // the order is slot (LIFO) first, token second: priority applies to the scarce
    // resource, which under server pressure is the token.
    private static func download(_ url: URL) async throws(AppError) -> Data {
        // An explicit request instead of data(from:) — which builds this same one
        // internally — so it can be logged.
        try await imageSession.perform(URLRequest(url: url), through: .shared).data
    }

    private static let imageSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        // No URLCache: the bytes are already saved to Caches/ by hand, and two disk
        // caches holding the same thing is paying twice for nothing. URLSession's
        // cache stays reserved for JSON responses, where the API's ETag earns its keep.
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 15
        return URLSession(configuration: configuration)
    }()
}

private extension CGImage {
    // What the decoded bitmap actually weighs in memory. The compressed file size
    // is useless as a cost figure — different orders of magnitude — and NSCache
    // would evict too late if it used that instead.
    var decodedByteCount: Int { bytesPerRow * height }
}
