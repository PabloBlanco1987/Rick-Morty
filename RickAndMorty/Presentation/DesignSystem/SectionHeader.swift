import SwiftUI

/// A section's title within a screen, with an optional accessory on the right — a
/// count, a status, whatever the section has to say about itself.
///
/// The accessory comes in via `@ViewBuilder` rather than plain text because the screen
/// decides whether there's anything to show: on the detail screen, the episode count
/// only appears once it's loaded, and that `if` lives inside the block without this
/// component needing to know.
struct SectionHeader<Accessory: View>: View {
    private let title: LocalizedStringResource
    private let accessory: Accessory

    init(_ title: LocalizedStringResource, @ViewBuilder accessory: () -> Accessory) {
        self.title = title
        self.accessory = accessory()
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.medium) {
            Text(title)
                .font(.sectionTitle)

            accessory
        }
    }
}

extension SectionHeader where Accessory == EmptyView {
    init(_ title: LocalizedStringResource) {
        self.init(title) { EmptyView() }
    }
}

#Preview("Section headers") {
    VStack(alignment: .leading, spacing: Theme.Spacing.xLarge) {
        SectionHeader(.characterDetailInformationTitle)

        SectionHeader(.characterDetailEpisodesTitle) {
            Text(.characterDetailEpisodesCountBadge(12))
                .font(.labelStrong)
                .tintedChip(in: .capsule)
        }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(Theme.Layout.screenMargin)
}
