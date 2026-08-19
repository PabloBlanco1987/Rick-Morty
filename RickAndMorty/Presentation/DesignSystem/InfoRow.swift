import SwiftUI

/// A data row: label on the left, value on the right.
///
/// Uses `ViewThatFits` because once type size grows, "Location" and "Citadel of Ricks"
/// no longer fit on one line; rather than truncate the value, the row splits into two.
/// That's what keeps the screen readable at accessibility sizes.
///
/// Lives in the design system, not the detail screen, because any screen showing an
/// item's data needs this piece: the next one — a location, an episode — is built on
/// this instead of re-solving the same layout problem.
struct InfoRow: View {
    let label: String
    let value: String
    let systemImage: String
    // Separator lives inside the row, not between rows in the parent, because its
    // indent depends on the icon size, which only the row knows.
    var showsDivider = true

    // Same base and reference style `IconTile` uses for its box: `@ScaledMetric` only
    // lives within the view that declares it, so the row declares its own to indent the
    // separator and the stacked variant. Starting from the same value, they scale
    // together.
    @ScaledMetric(relativeTo: .subheadline) private var iconSide: CGFloat = IconTile.baseSide

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsDivider {
                Divider()
                    .padding(.leading, Theme.Spacing.large + iconSide + Theme.Spacing.medium)
            }

            ViewThatFits(in: .horizontal) {
                horizontalLayout

                verticalLayout
            }
            // Full width, left-aligned: the vertical variant is narrower than the row,
            // and without this the container centered it, leaving icons misaligned
            // with the row above.
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var horizontalLayout: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.medium) {
            IconTile(systemImage: systemImage)

            labelText

            Spacer(minLength: Theme.Spacing.large)

            valueText
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, Theme.Spacing.large)
        .padding(.vertical, Theme.Spacing.medium)
    }

    private var verticalLayout: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            HStack(spacing: Theme.Spacing.medium) {
                IconTile(systemImage: systemImage)
                labelText
            }

            valueText
                .padding(.leading, iconSide + Theme.Spacing.medium)
        }
        .padding(.horizontal, Theme.Spacing.large)
        .padding(.vertical, Theme.Spacing.medium)
    }

    private var labelText: some View {
        Text(label)
            .font(.label)
            .foregroundStyle(.secondary)
    }

    private var valueText: some View {
        Text(value)
            .font(.labelEmphasis)
            .fixedSize(horizontal: false, vertical: true)
    }
}

#Preview("Info rows") {
    VStack(spacing: 0) {
        InfoRow(
            label: String(localized: .characterDetailSpeciesLabel),
            value: "Human",
            systemImage: "sparkles",
            showsDivider: false
        )

        InfoRow(
            label: String(localized: .characterDetailLocationLabel),
            value: "Citadel of Ricks",
            systemImage: "mappin.and.ellipse"
        )
    }
    .cardSurface()
    .padding(Theme.Layout.screenMargin)
}
