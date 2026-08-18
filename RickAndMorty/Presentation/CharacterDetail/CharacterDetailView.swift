import SwiftUI

// La ficha de un personaje: quién es, de dónde viene y en qué episodios sale.
//
// La pantalla se pinta en dos tiempos a propósito. La cabecera sale con lo que ya venía
// de la lista, así que al tocar una celda hay contenido en el primer frame; lo único
// que muestra que algo está cargando es la sección de episodios, que es lo único que de
// verdad hay que ir a buscar. Enseñar un spinner a pantalla completa por encima de
// datos que ya se tenían es la forma más fácil de que una app parezca lenta sin serlo.
struct CharacterDetailView: View {
    @State private var viewModel: CharacterDetailViewModel

    // Cuántas veces se ha pedido cargar: 0 es el arranque y cada "Try again" suma uno.
    // Es la identidad de la tarea de carga, y así la vista es la dueña de todas: al salir
    // de la pantalla SwiftUI la cancela, y un reintento cancela al anterior si aún estaba
    // en vuelo. Con un Task { } suelto en el botón, la petición seguía después de hacer
    // pop y escribía el estado en un view model que ya nadie miraba.
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
            // El mismo margen que el listado: al navegar de una pantalla a la otra, el
            // contenido no da un salto lateral.
            .contentMargins(Theme.Layout.screenMargin, for: .scrollContent)
            .accessibilityIdentifier("character-detail")
        }
    }

    // MARK: - Cabecera

    @ViewBuilder
    private var header: some View {
        if let character = viewModel.character {
            VStack(alignment: .leading, spacing: Theme.Spacing.large) {
                CachedAsyncImage(url: character.imageURL)
                    .aspectRatio(1, contentMode: .fit)
                    // Con tope, porque los avatares de la API son de 300 px y en un iPad
                    // a pantalla completa el ancho entero serían mil puntos de imagen
                    // estirada. En un iPhone el tope no llega a aplicarse.
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

    // MARK: - Información

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

                    InfoRow(
                        label: String(localized: .characterDetailOriginLabel),
                        // El lugar desconocido se dice como los demás valores
                        // desconocidos de la ficha, en el idioma del usuario, en vez de
                        // colar el "unknown" en minúscula que manda la API
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

    // MARK: - Episodios

    @ViewBuilder
    private var episodes: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
            SectionHeader(.characterDetailEpisodesTitle) {
                // El recuento solo aparece cuando hay algo que contar: un "0" al lado del
                // título mientras cargan es un dato que además es mentira.
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

                // Los textos salen del catálogo aunque no se vean: solo dan el ancho de
                // la barra gris, y así no queda ningún literal de interfaz en el código
                EpisodeRow(
                    episode: Episode(
                        id: index,
                        name: String(localized: .characterDetailSkeletonEpisodeName),
                        code: String(localized: .characterDetailSkeletonEpisodeCode),
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

// El código a la izquierda y el título a la derecha; con tamaños de accesibilidad, el
// código arriba y el título debajo. En horizontal, un "S01E01" a 43 pt de monoespaciada
// se comía la mitad de la fila y al título le quedaban cinco letras por línea: se partía
// "Episo-de" con guion y el propio código se doblaba en dos.
private struct EpisodeRow: View {
    let episode: Episode

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.small))
            : AnyLayout(HStackLayout(alignment: .center, spacing: Theme.Spacing.medium))

        layout {
            Text(episode.code)
                .font(.chipCode)
                // Un código no se parte: antes que doblarse cede la línea al título
                .fixedSize()
                .tintedChip(in: .rect(cornerRadius: Theme.Radius.chip))

            VStack(alignment: .leading, spacing: Theme.Spacing.xxSmall) {
                Text(episode.name)
                    .font(.label)
                    .fixedSize(horizontal: false, vertical: true)

                if let airDate = episode.formattedAirDate {
                    Text(airDate)
                        .font(.metadata)
                        .foregroundStyle(.secondary)
                }
            }
        }
        // El ancho lo pone la fila y no un Spacer: en la variante vertical un Spacer
        // empujaría hacia abajo en vez de hacia la derecha
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Spacing.large)
        .padding(.vertical, Theme.Spacing.medium)
    }
}

extension Episode {
    // El dominio guarda una Date y presentación decide cómo se escribe, así que la fecha
    // sale en el formato del dispositivo: "2 dic 2013" en España y "Dec 2, 2013" en
    // Estados Unidos, sin que el modelo sepa nada de locales.
    //
    // La zona horaria va fijada a GMT a propósito, y es lo mismo que hace el mapper al
    // parsear: una fecha de emisión es un día de calendario, no un instante. La API dice
    // "December 2, 2013" sin hora, así que se guarda como la medianoche de ese día en
    // GMT; si aquí se formatease en la zona del dispositivo, en América —cualquier
    // zona con desfase negativo— esa medianoche cae el día anterior y el piloto saldría
    // emitido el 1 de diciembre. El locale, en cambio, sí es el del usuario.
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
