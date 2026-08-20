import SwiftUI

/// A character's detail: who they are, where they're from, which episodes they're in.
/// Paints in two beats on purpose — the header comes from what the list already had,
/// so there's content on the first frame; only the episodes section shows loading,
/// since that's the only thing actually fetched. A full-screen spinner over data
/// already on hand is the easiest way for an app to look slow without being slow.
struct CharacterDetailView: View {
    @State private var viewModel: CharacterDetailViewModel

    // How many times a load's been requested: 0 is startup, each "Try again" adds one.
    // It's the load task's identity, so the view owns every one of them — SwiftUI
    // cancels it on dismiss, and a retry cancels whichever was still in flight. A loose
    // Task { } on the button would keep running after pop and write into a view model
    // nobody's watching anymore.
    @State private var loadAttempt = 0

    @MainActor
    init(
        character: Character,
        fetchCharacterDetail: FetchCharacterDetailUseCase
    ) {
        _viewModel = State(
            initialValue: CharacterDetailViewModel(
                characterID: character.id,
                known: character,
                fetchCharacterDetail: fetchCharacterDetail
            )
        )
    }

    var body: some View {
        content
            .navigationTitle(viewModel.character?.name ?? "")
            .navigationBarTitleDisplayMode(.inline)
            .task(id: loadAttempt) {
                if loadAttempt == 0 {
                    await viewModel.onAppear()
                } else {
                    await viewModel.retry()
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if case .failed(let error) = viewModel.state,
           !viewModel.hasContentOnScreen {
            errorView(error)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xxLarge) {
                    header
                    facts
                    episodes
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            // Same margin as the list: content doesn't shift sideways when navigating
            // between the two screens.
            .contentMargins(Theme.Layout.screenMargin, for: .scrollContent)
            .accessibilityIdentifier("character-detail")
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        if let character = viewModel.character {
            VStack(alignment: .leading, spacing: Theme.Spacing.large) {
                CachedAsyncImage(url: character.imageURL)
                    .aspectRatio(1, contentMode: .fit)
                    // Capped: the API's avatars are 300px, and full-width on an iPad
                    // would stretch that to a thousand points. Doesn't kick in on iPhone.
                    .frame(maxWidth: Theme.Layout.heroImageMaxWidth)
                    .clipShape(.rect(cornerRadius: Theme.Radius.hero))

                VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
                    Text(character.name)
                        .font(.screenTitle)
                        .fixedSize(horizontal: false, vertical: true)

                    CharacterStatusBadge(status: character.status)
                }
            }
        }
    }

    // MARK: - Facts

    @ViewBuilder
    private var facts: some View {
        if let character = viewModel.character {
            VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
                SectionHeader(.characterDetailInformationTitle)

                VStack(spacing: 0) {
                    InfoRow(
                        label: String(localized: .characterDetailSpeciesLabel),
                        value: character.species,
                        systemImage: "sparkles",
                        showsDivider: false
                    )

                    if let type = character.type {
                        InfoRow(
                            label: String(localized: .characterDetailTypeLabel),
                            value: type,
                            systemImage: "tag"
                        )
                    }

                    InfoRow(
                        label: String(localized: .characterDetailGenderLabel),
                        value: character.gender.displayName,
                        systemImage: "person"
                    )

                    // TODO: [Out of scope · README §8] Places and episodes as destinations.
                    /*
                     Reason: the two rows below and every `EpisodeRow` further down are
                     this app's natural way into the other two collections the API
                     serves, and all three are plain text. Nothing to open, because
                     there is no location screen and no episode screen to open.
                     Ready to plug in: navigation here already goes by value, so each
                     row becomes a `NavigationLink(value:)` as soon as it carries an id
                     (see `CharacterMapper` for the place's), pushing its destination
                     the same way the list pushes this screen.
                     */
                    InfoRow(
                        label: String(localized: .characterDetailOriginLabel),
                        // An unknown place reads like the detail screen's other
                        // unknown values, in the user's language, instead of leaking
                        // the API's lowercase "unknown".
                        value: character.origin ?? String(localized: .characterDetailUnknownPlace),
                        systemImage: "globe"
                    )

                    InfoRow(
                        label: String(localized: .characterDetailLocationLabel),
                        value: character.location ?? String(localized: .characterDetailUnknownPlace),
                        systemImage: "mappin.and.ellipse"
                    )
                }
                .cardSurface()
            }
        }
    }

    // MARK: - Episodes

    @ViewBuilder
    private var episodes: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
            SectionHeader(.characterDetailEpisodesTitle) {
                // The count only shows once there's something to count — a "0" next
                // to the title while loading would also be a lie.
                if !viewModel.episodes.isEmpty {
                    Text(.characterDetailEpisodesCountBadge(viewModel.episodes.count))
                        .font(.labelStrong)
                        .tintedChip(in: .capsule)
                }
            }

            switch viewModel.state {
            case .idle, .loading:
                episodeSkeleton

            case .loaded, .empty:
                if viewModel.episodes.isEmpty {
                    Text(.characterDetailNoEpisodes)
                        .font(.label)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, Theme.Spacing.small)
                } else {
                    episodeList
                }

            case .failed(let error):
                InlineErrorView(error: error, retryTitle: .characterDetailRetryButton) {
                    loadAttempt += 1
                }
            }
        }
    }

    private var episodeList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(
                Array(viewModel.episodes.enumerated()),
                id: \.element.id
            ) { index, episode in

                if index > 0 {
                    Divider()
                }

                EpisodeRow(episode: episode)
            }
        }
        .cardSurface()
    }

    private var episodeSkeleton: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<Theme.Layout.skeletonEpisodeCount, id: \.self) { index in
                if index > 0 {
                    Divider()
                }

                // The name comes from the catalog even though it's never read — it only
                // sets the gray bar's width, so no interface literal sits in the code.
                // The code needs no key of its own anymore: its words already come from
                // the catalog through the format, and 1 and 1 are numbers, not text.
                EpisodeRow(
                    episode: Episode(
                        id: index,
                        name: String(localized: .characterDetailSkeletonEpisodeName),
                        code: Episode.Code(season: 1, number: 1),
                        airDate: nil
                    )
                )
            }
        }
        .cardSurface()
        .redacted(reason: .placeholder)
    }

    private func errorView(_ error: AppError) -> some View {
        ErrorStateView(error: error, retryTitle: .characterDetailRetryButton) {
            loadAttempt += 1
        }
    }
}

/// Title on top, then where the episode sits and when it aired.
///
/// The title leads because "Season 1 · Episode 8" is a phrase, not a token, and a phrase
/// can't hold the narrow left column the monospaced "S01E01" used to: at any text size it
/// would take most of the row and leave the title a few letters per line. Turned into the
/// row's second line it costs nothing, reads as words, and puts the name — the thing
/// being scanned for — first.
///
/// Chip and date share that second line while both fit, and stack when they don't.
private struct EpisodeRow: View {
    let episode: Episode

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            Text(episode.name)
                .font(.labelEmphasis)
                .fixedSize(horizontal: false, vertical: true)

            // `ViewThatFits` over a type-size threshold: what decides here is whether the
            // two actually fit, and that depends on the season, the date's language and
            // the width as much as on the text size. Neither variant truncates, so the
            // fallback is a taller row, never a cut word.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Theme.Spacing.medium) {
                    code
                    airDate
                }

                VStack(alignment: .leading, spacing: Theme.Spacing.small) {
                    code
                    airDate
                }
            }
        }
        // Width comes from the row, not a Spacer: in the stacked variant a Spacer would
        // push down instead of right.
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Spacing.large)
        .padding(.vertical, Theme.Spacing.medium)
    }

    // Absent when the API's code didn't parse: the row loses its chip, not its meaning.
    @ViewBuilder
    private var code: some View {
        if let code = episode.code {
            Text(code.displayName)
                .font(.chipLabel)
                .tintedChip(in: .rect(cornerRadius: Theme.Radius.chip))
        }
    }

    @ViewBuilder
    private var airDate: some View {
        if let airDate = episode.formattedAirDate {
            Text(airDate)
                .font(.metadata)
                .foregroundStyle(.secondary)
        }
    }
}

extension Episode.Code {
    // "Season 1 · Episode 8". The numbers come from the domain and the words from the
    // catalog, so nothing here knows about the API's "S01E08": the padding zeros never
    // reach the screen, and a translation can reword — or reorder — the two numbers.
    var displayName: String {
        String(localized: .characterDetailEpisodeCode(season, number))
    }
}

extension Episode {
    // The domain stores a Date, presentation decides how it reads, so the date comes
    // out in the device's format — "2 dic 2013" in Spain, "Dec 2, 2013" in the US —
    // with the model knowing nothing about locales.
    //
    // The time zone is pinned to GMT on purpose, matching the mapper's parsing: an air
    // date is a calendar day, not an instant. The API says "December 2, 2013" with no
    // time, stored as that day's midnight GMT; formatting in the device's zone would
    // put that midnight a day earlier anywhere west of Greenwich, airing the episode a
    // day early. The locale, though, is the user's.
    var formattedAirDate: String? {
        airDate?.formatted(Date.FormatStyle(timeZone: .gmt).day().month(.abbreviated).year())
    }
}

extension Character.Gender {
    var displayName: String {
        switch self {
        case .female: String(localized: .characterGenderFemale)
        case .male: String(localized: .characterGenderMale)
        case .genderless: String(localized: .characterGenderGenderless)
        case .unknown: String(localized: .characterGenderUnknown)
        }
    }
}

#Preview {
    NavigationStack {
        CharacterDetailView(
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
            ),
            fetchCharacterDetail: AppDependencies.live().fetchCharacterDetail
        )
    }
}
