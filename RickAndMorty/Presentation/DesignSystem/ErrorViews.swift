import SwiftUI

// How a failure is shown, in the two forms the app needs.
//
// The difference isn't style, it's what the failure affects. If there's nothing else to
// show, the error *is* the screen and takes the content's place (`ErrorStateView`). If
// what's already on screen is still valid — a loaded list missing its next page, a
// detail missing its episodes — the error is just another piece within the content and
// doesn't take over what the user was already looking at (`InlineErrorView`).
//
// The button's text is set by the caller, not the component: "Try again" lives in the
// catalog once per screen, so each screen can phrase it its own way without this needing
// to know where it's used.

/// The failure when there's nothing else to show. Built on `ContentUnavailableView`
/// because it's what iOS uses for this across its own apps: users already know how to
/// read it, and it comes with its typography, margins, and large-text behavior for free.
struct ErrorStateView: View {
    let error: AppError
    let retryTitle: LocalizedStringResource
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(error.title, systemImage: error.systemImage)
        } description: {
            Text(error.message)
        } actions: {
            Button(retryTitle, action: retry)
                .buttonStyle(.borderedProminent)
        }
    }
}

/// The failure of one part, within content that's still good. In a card, left-aligned
/// like the rest of the app's blocks — reads as "this part didn't load", not "the screen
/// failed".
struct InlineErrorView: View {
    let error: AppError
    let retryTitle: LocalizedStringResource
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            Label(error.title, systemImage: error.systemImage)
                .font(.labelStrong)

            Text(error.message)
                .font(.message)
                .foregroundStyle(.secondary)

            Button(retryTitle, action: retry)
                .buttonStyle(.bordered)
                .padding(.top, Theme.Spacing.xSmall)
        }
        // Text wraps at large sizes; without this the card would shrink to its longest
        // line's width.
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.large)
        .cardSurface()
    }
}

#Preview("Error state") {
    ErrorStateView(error: .offline, retryTitle: .characterListRetryButton) {}
}

#Preview("Inline error") {
    InlineErrorView(error: .server(statusCode: 503), retryTitle: .characterDetailRetryButton) {}
        .padding(Theme.Layout.screenMargin)
}
