import SwiftUI

/// The box for a symbol, tinted, to put in front of a piece of data.
///
/// The symbol is decoration: the label next to it already says what the row is about,
/// so the icon can use the accent color without its contrast mattering. If an icon ever
/// became the sole carrier of data, this would no longer hold — which is exactly what
/// this comment needs to remind.
struct IconTile: View {
    let systemImage: String
    var tint: Color = Theme.Tint.accent

    // Side scales with type size. Fixed at 28 pt, the symbol overflowed its background
    // and overlapped the label at AX2.
    @ScaledMetric(relativeTo: .subheadline) private var side: CGFloat = IconTile.baseSide

    // Unscaled size, for anything that must align with the box: `InfoRow` indents its
    // separator and stacked variant by this same number. `@ScaledMetric` only exists
    // within the view that declares it, so the row declares its own with this same base
    // and `relativeTo:`; they scale identically since they start from the same value.
    static let baseSide: CGFloat = 28

    var body: some View {
        Image(systemName: systemImage)
            .font(.labelEmphasis)
            .foregroundStyle(tint)
            .frame(width: side, height: side)
            .background(Theme.Tint.fill(tint), in: .rect(cornerRadius: Theme.Radius.chip))
    }
}

#Preview("Icon tiles") {
    HStack(spacing: Theme.Spacing.medium) {
        IconTile(systemImage: "sparkles")
        IconTile(systemImage: "globe")
        IconTile(systemImage: "mappin.and.ellipse")
    }
    .padding(Theme.Layout.screenMargin)
}
