import SwiftUI

/// The app's two surfaces: the card and the chip.
///
/// These are modifiers, not wrapping views, on purpose. A `CardView { … }` would force
/// content into another container and change the view tree — exactly what you don't want
/// in a cell compared with `.equatable()` hundreds of times — while a modifier applies at
/// the end, reads in paint order, and adds no layout layer.
extension View {
    // Background for any content surface: list cell, detail info block, episode list,
    // inline error.
    //
    // The clip isn't optional here — a rounded background doesn't clip what sits on top
    // of it, so without it a cell's (rectangular) image pokes square corners past the
    // rounded background, leaving a mismatched top and bottom edge. Where nothing
    // overflows, clipping costs nothing.
    func cardSurface(cornerRadius: CGFloat = Theme.Radius.card) -> some View {
        self
            .background(.background.secondary, in: .rect(cornerRadius: cornerRadius))
            .clipShape(.rect(cornerRadius: cornerRadius))
            .contentShape(.rect(cornerRadius: cornerRadius))
    }

    // Tinted fill used by chips: status badge, episode count, an episode's code.
    //
    // Tint color is a parameter because it isn't always the accent: the status badge is
    // tinted with its own status color — green, red, or gray — which is exactly the data
    // it's conveying. Shape too, since a pill and a rounded rect say different things:
    // pill is a label, rect is a row piece.
    //
    // Never parameterized: opacity or colored text — chip content always uses the
    // primary color. Green text on its own tint drops to 1.9:1 in light mode, far below
    // WCAG's 4.5:1, and the fill already carries the color.
    func tintedChip(_ tint: Color = Theme.Tint.accent, in shape: some Shape, opaque: Bool = false) -> some View {
        self
            // Primary color is set by the chip, not each call site: it's a contrast
            // rule, not a preference — left to callers it eventually produces a chip
            // with text in its own tint. Applied inside the fill, so it wins over any
            // external `foregroundStyle`.
            .foregroundStyle(.primary)
            .padding(.horizontal, Theme.Spacing.medium)
            .padding(.vertical, Theme.Spacing.xSmall)
            .background {
                // `opaque` is for chips floating over an image, where a 12% tint would
                // let the photo show through and the chip would lose contrast with its
                // own text. Backed by the app background, not white — white would be a
                // spotlight in dark mode.
                if opaque {
                    shape.fill(.background)
                }

                shape.fill(Theme.Tint.fill(tint))
            }
    }
}

#Preview("Surfaces") {
    VStack(alignment: .leading, spacing: Theme.Spacing.xLarge) {
        Text(verbatim: "Card surface")
            .font(.cardTitle)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.medium)
            .cardSurface()

        HStack(spacing: Theme.Spacing.medium) {
            Text(verbatim: "12 episodes")
                .font(.chipLabel)
                .tintedChip(in: .capsule)

            Text(verbatim: "S01E01")
                .font(.chipCode)
                .tintedChip(in: .rect(cornerRadius: Theme.Radius.chip))

            Text(verbatim: "Alive")
                .font(.chipLabel)
                .tintedChip(in: .capsule, opaque: true)
        }
    }
    .padding(Theme.Layout.screenMargin)
}
