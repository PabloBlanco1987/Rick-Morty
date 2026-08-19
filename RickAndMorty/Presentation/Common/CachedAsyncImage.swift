import CoreGraphics
import SwiftUI

/// Growing delay between attempts, as long as the cell stays on screen. Two retry
/// layers with two different jobs, worth keeping straight so they don't look like the
/// same thing twice: ImageCache retries a request's stumble right away — hundreds of
/// milliseconds — once for every cell waiting on that download. This one covers the
/// multi-second bad stretch: .task doesn't refire on its own, so without this a server
/// down for five seconds leaves that gap gray until the cell scrolls off and back on.
/// Starts where the other one ends, in seconds, and is bounded — if the failure isn't
/// passing, insisting just burns battery to show the same thing.
///
/// Outside the type because CachedAsyncImage is generic, and a generic can't hold a
/// stored static property.
private let imageRetryDelays: [Duration] = [
    .seconds(1),
    .seconds(3),
    .seconds(8),
]

/// ImageCache's consuming view. Doesn't use SwiftUI's AsyncImage on purpose: it
/// doesn't downsample to cell size, keeps nothing between appearances (scrolling back
/// re-downloads), and doesn't share a request between two views asking for the same
/// URL. In a grid of 826 avatars, those three are exactly what shows.
struct CachedAsyncImage<Placeholder: View>: View {
    private let url: URL?
    private let placeholder: Placeholder

    @Environment(\.imageCache) private var cache
    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var image: CGImage?
    @State private var pointSize: CGSize = .zero

    // Starts true on purpose: outside a ScrollView — a preview, a test — nobody
    // reports visibility, and loading anyway is the correct behavior there.
    @State private var isOnScreen = true

    init(url: URL?, @ViewBuilder placeholder: () -> Placeholder) {
        self.url = url
        self.placeholder = placeholder()
    }

    var body: some View {
        ZStack {
            // The placeholder never leaves the tree, only fades out — so the image's
            // slot has a size from the first layout pass, and cells don't jump in
            // height as each image arrives.
            placeholder
                .opacity(image == nil ? 1 : 0)

            if let image {
                Image(decorative: image, scale: displayScale, orientation: .up)
                    .resizable()
                    .scaledToFill()
            }
        }
        .clipped()
        .onGeometryChange(for: CGSize.self) { proxy in
            // Rounded to whole points so half a point of layout jitter doesn't
            // trigger another decode.
            CGSize(width: proxy.size.width.rounded(.up), height: proxy.size.height.rounded(.up))
        } action: { pointSize = $0 }
        // Real visibility, not the same as being alive: LazyVGrid creates cells as
        // needed but doesn't destroy them on scroll-past, so .task alone never
        // cancels and a fast scroll leaves hundreds of live downloads for cells left
        // ten screens behind. The threshold is low so a sliver on screen counts.
        .onScrollVisibilityChange(threshold: 0.01) { isOnScreen = $0 }
        // With id: the load cancels and restarts on its own whenever anything that
        // defines the request changes, with nothing to remember to clean up.
        .task(id: Request(url: url, size: pointSize, isOnScreen: isOnScreen)) { await load() }
    }

    // Identifies what needs loading. Size is included because the image decodes at
    // cell size — a resized cell makes what's loaded stale. Visibility is included
    // because leaving the screen has to cancel the download, and returning has to
    // restart it.
    private struct Request: Equatable {
        let url: URL?
        let size: CGSize
        let isOnScreen: Bool
    }

    private func load() async {
        // No URL — the API sends empty ones — means no image to show.
        guard let url else {
            image = nil
            return
        }

        // Off screen, or before the first layout pass, there's nothing to request.
        // What's already loaded isn't cleared here: the cell will come back, and
        // when it does it has to appear whole, not empty.
        guard isOnScreen, pointSize.width > 0, pointSize.height > 0 else { return }

        for attempt in 0...imageRetryDelays.count {
            if attempt > 0 {
                do {
                    try await Task.sleep(for: imageRetryDelays[attempt - 1])
                } catch {
                    // The wait was cancelled: the cell is leaving, nobody left to show.
                    return
                }
            }

            do {
                let loaded = try await cache.image(for: url, size: pointSize, scale: displayScale)
                // Only fades what actually had to be fetched. What was already in
                // memory appears instantly — a fade on scrolling back reads as a
                // flicker, not an arrival.
                let shouldFade = loaded.origin != .memory
                withAnimation(shouldFade ? Theme.Motion.fade(reduceMotion: reduceMotion) : nil) {
                    image = loaded.image
                }
                return
            } catch {
                // If this cell is what got cancelled, it's leaving the screen and
                // there's nothing left to retry for.
                if Task.isCancelled { return }
                // And only insists on what waiting can fix. A 404 will still be a
                // 404 in eight seconds, and bytes that don't decode won't improve
                // either — repeating those burns requests, and limiter tokens, on an
                // image that's never coming, multiplied across every cell showing it.
                guard error.isRetryable else { return }
            }
        }

        // Attempts exhausted: the placeholder stays. In a grid, an error icon every
        // other cell is more noise than information, and the character — the actual
        // content — is still there with its name and status.
        /*
         TODO: [Out of scope · README §8] Retrying images from the list.
         Reason: past this point the gap doesn't fill until the user scrolls the cell
         off screen and back on. Left this way on purpose — the good fix, having a
         list retry also retry its failed images, needs a retry signal flowing down
         from the view model.
         Ready to plug in: would come in as an environment value folded into
         `Request`, this task's identity, so bumping it would refire every cell at
         once without touching `load()`.
         */

        // `image` is left untouched: if the cell already had one and the reload
        // failed, showing what's there beats clearing the slot.
    }
}

extension CachedAsyncImage where Placeholder == ImagePlaceholder {
    init(url: URL?) {
        self.init(url: url) { ImagePlaceholder() }
    }
}

/// A neutral image slot: no spinner, no error icon. A spinner per cell in a grid is a
/// field of spinning things, and for something as quick as a small image, the wait
/// reads better as a still gap.
struct ImagePlaceholder: View {
    var body: some View {
        Rectangle()
            .fill(.fill.tertiary)
            .overlay {
                Image(systemName: "person.fill")
                    .font(.placeholderIcon)
                    .foregroundStyle(.tertiary)
            }
    }
}

extension EnvironmentValues {
    // The cache arrives through the environment, not AppDependencies: what size an
    // image needs is a presentation-layer decision, not the domain's, so a preview or
    // test can swap in its own without touching the composition root or threading the
    // cache through every intermediate view's init.
    @Entry var imageCache: ImageCache = .shared
}

#Preview("Placeholder and loading") {
    HStack(spacing: Theme.Spacing.large) {
        CachedAsyncImage(url: nil)
            .frame(width: 120, height: 120)
            .clipShape(.rect(cornerRadius: Theme.Radius.card))

        CachedAsyncImage(url: URL(string: "https://rickandmortyapi.com/api/character/avatar/1.jpeg"))
            .frame(width: 120, height: 120)
            .clipShape(.rect(cornerRadius: Theme.Radius.card))
    }
    .padding()
}
