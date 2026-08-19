import SwiftUI

/// Notice that a pull-to-refresh failed and the visible list may be stale.
///
/// A notice, not an error screen, because the list is still valid — only the check for
/// changes failed, and that fits in two lines. Dismisses after six seconds, on tap, or
/// sooner if another refresh succeeds, which is what the view model does when it clears
/// `refreshFailure`.
///
/// No queue: there's only one emitter. If a second refresh fails while this notice is
/// showing, the current one stays (with the new error text if it differs), and the
/// countdown restarts only then — a repeated identical failure doesn't reset anything.
struct RefreshFailureNotice: View {
    let error: AppError
    let dismiss: () -> Void

    private static let lifetime: Duration = .seconds(6)

    var body: some View {
        // Whole button, not text plus a separate X, so dismissing is a tap anywhere
        Button(action: dismiss) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.medium) {
                Image(systemName: error.systemImage)
                    .font(.labelStrong)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: Theme.Spacing.xxSmall) {
                    Text(error.title)
                        .font(.labelStrong)
                    Text(.characterListRefreshFailedMessage)
                        .font(.message)
                        .foregroundStyle(.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
            .padding(Theme.Spacing.large)
            .frame(maxWidth: Theme.Layout.noticeMaxWidth)
            // Material and border are its own, not `cardSurface` — this isn't a content
            // surface, it's a piece floating over the list while it's read and then
            // dismisses itself. The blur separates it from what's underneath without
            // needing a shadow.
            .background(.regularMaterial, in: .rect(cornerRadius: Theme.Radius.card))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.card)
                    .strokeBorder(.separator, lineWidth: 0.5)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("refresh-failed")
        // Keyed by id: if the error changes while the notice is showing, the countdown
        // restarts; when the notice disappears, SwiftUI cancels the task automatically
        .task(id: error) {
            do {
                try await Task.sleep(for: Self.lifetime)
            } catch {
                // Cancelled: the notice already dismissed some other way
                return
            }
            dismiss()
        }
    }
}

#Preview {
    VStack(spacing: Theme.Spacing.large) {
        RefreshFailureNotice(error: .offline) {}
        RefreshFailureNotice(error: .server(statusCode: 503)) {}
    }
    .padding()
}
