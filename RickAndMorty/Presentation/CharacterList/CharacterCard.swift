import SwiftUI

/// The list's cell.
/// `Equatable` isn't decoration: with `.equatable()` SwiftUI compares the whole cell
/// against the previous one and skips rebuilding the body if the character hasn't
/// changed. Appending a page only builds the 20 new cells; the previous 800 are
/// skipped by a struct comparison. This works because `Character` is a value and the
/// cell holds nothing else — attaching a closure would break comparability and the
/// optimization would silently vanish.
struct CharacterCard: View, Equatable {
    let character: Character

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CachedAsyncImage(url: character.imageURL)
                // Square: API avatars are square, and fixing the ratio before the
                // image loads prevents the whole row from jumping in height as each
                // one lands.
                .aspectRatio(1, contentMode: .fit)
                .overlay(alignment: .topTrailing) {
                    CharacterStatusBadge(status: character.status)
                        .padding(Theme.Spacing.medium)
                }

            // No line limit on the name, two lines for the species. With a cap of two,
            // "Abadango Cluster Princess" truncated from xxLarge in two columns; with
            // one, the species clipped "Mythological Creature" even at normal size.
            // The cell already stretches to row height, so an extra line only costs
            // height — it doesn't clip the neighbor.
            VStack(alignment: .leading, spacing: Theme.Spacing.small) {
                Text(character.name)
                    .font(.cardTitle)
                    .fixedSize(horizontal: false, vertical: true)

                Text(character.species)
                    .font(.label)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.medium)
        }
        // Stretched to row height so two cells with names of different length don't
        // leave the background half-drawn
        .frame(maxHeight: .infinity, alignment: .top)
        .cardSurface()
    }
}

/// The same space a cell occupies, without data.
/// Renders the real shape rather than a generic rectangle, so nothing shifts once
/// characters arrive — loading reads as content filling in, not as a jump. Uses the
/// same tokens as the cell, so the placeholder and its content match by construction,
/// not by having copied it correctly.
struct CharacterCardSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(.fill.tertiary)
                .aspectRatio(1, contentMode: .fit)
                .overlay(alignment: .topTrailing) {
                    CharacterStatusBadge(status: .unknown)
                        .padding(Theme.Spacing.medium)
                }

            VStack(alignment: .leading, spacing: Theme.Spacing.small) {
                Text(.characterCardSkeletonNameLabel)
                    .font(.cardTitle)

                Text(.characterCardSkeletonSpeciesLabel)
                    .font(.label)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.medium)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .cardSurface()
    }
}

#Preview("Card") {
    CharacterCard(
        character: Character(
            id: 1,
            name: "Rick Sanchez",
            status: .alive,
            species: "Human",
            type: nil,
            gender: .male,
            origin: "Earth (C-137)",
            location: "Citadel of Ricks",
            imageURL: URL(string: "https://rickandmortyapi.com/api/character/avatar/1.jpeg"),
            episodeIDs: [1, 2]
        )
    )
    .frame(width: 180)
    .padding()
}

#Preview("Skeleton") {
    CharacterCardSkeleton()
        .redacted(reason: .placeholder)
        .frame(width: 180)
        .padding()
}
