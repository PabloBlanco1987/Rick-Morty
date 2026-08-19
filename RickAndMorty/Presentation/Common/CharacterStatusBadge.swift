import SwiftUI

/// A character's status, with color and text. Color alone wouldn't do — anyone who
/// can't tell red from green (~8% of men) would lose the data, and color doesn't
/// survive a black-and-white screenshot or high contrast mode either. Color supports,
/// it doesn't inform. Lives in `Common`, not the list folder, because both screens use
/// it — the same badge in the cell's corner and under the name on the detail screen —
/// which is exactly what makes it read as the same piece of data.
struct CharacterStatusBadge: View {
    let status: Character.Status

    // Dot and spacing grow with the text: at accessibility sizes letters reach 43pt,
    // and a fixed 8pt dot would shrink to a speck beside them.
    @ScaledMetric(relativeTo: .caption) private var dotSize: CGFloat = 8
    @ScaledMetric(relativeTo: .caption) private var spacing: CGFloat = Theme.Spacing.small

    var body: some View {
        HStack(spacing: spacing) {
            Circle()
                .fill(status.tint)
                .frame(width: dotSize, height: dotSize)

            Text(status.displayName)
                // Text in primary color, not the status color — tintedChip does this
                // for every chip in the app: green on light green misses WCAG's
                // 4.5:1 contrast, and the dot already carries the color.
                .font(.chipLabel)
        }
        // Opaque because this chip floats over the character's photo: without a solid
        // base, a 12% tint would let the image show through and the text would lose
        // its background.
        .tintedChip(status.tint, in: .capsule, opaque: true)
    }
}

extension Character.Status {
    // Text and color live in Presentation: the domain knows nothing about colors or
    // languages, so the same case can paint differently on the detail screen untouched.
    var displayName: String {
        switch self {
        case .alive: String(localized: .characterStatusAlive)
        case .dead: String(localized: .characterStatusDead)
        case .unknown: String(localized: .characterStatusUnknown)
        }
    }

    var tint: Color {
        switch self {
        case .alive: Theme.Tint.accent
        case .dead: .red
        case .unknown: .gray
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
        ForEach(Character.Status.allCases, id: \.self) { status in
            CharacterStatusBadge(status: status)
        }
    }
    .padding()
}
