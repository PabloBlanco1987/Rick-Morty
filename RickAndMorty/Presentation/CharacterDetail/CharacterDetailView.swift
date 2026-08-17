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
                VStack(alignment: .leading, spacing: 32) {
                    header
                    facts
                    episodes
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentMargins(20, for: .scrollContent)
            .accessibilityIdentifier("character-detail")
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        if let character = viewModel.character {
            VStack(alignment: .leading, spacing: 16) {
                CachedAsyncImage(url: character.imageURL)
                    .aspectRatio(1, contentMode: .fit)
                    // Con tope: los avatares de la API son de 300 px, y en un iPad a
                    // pantalla completa el ancho entero serían mil puntos de imagen
                    // estirada. En un iPhone el tope no llega a aplicarse.
                    .frame(maxWidth: 360)
                    .clipShape(.rect(cornerRadius: 20))

                VStack(alignment: .leading, spacing: 10) {
                    Text(character.name)
                        .font(.largeTitle.bold())
                        .fixedSize(horizontal: false, vertical: true)

                    CharacterStatusBadge(status: character.status)
                }
            }
        }
    }

    // MARK: - Information

    @ViewBuilder
    private var facts: some View {
        if let character = viewModel.character {
            VStack(alignment: .leading, spacing: 12) {
                Text(.characterDetailInformationTitle)
                    .font(.title2.bold())

                VStack(spacing: 0) {
                    DetailRow(
                        label: String(localized: .characterDetailSpeciesLabel),
                        value: character.species,
                        systemImage: "sparkles",
                        showsDivider: false
                    )

                    if let type = character.type {
                        DetailRow(
                            label: String(localized: .characterDetailTypeLabel),
                            value: type,
                            systemImage: "tag"
                        )
                    }

                    DetailRow(
                        label: String(localized: .characterDetailGenderLabel),
                        value: character.gender.displayName,
                        systemImage: "person"
                    )

                    DetailRow(
                        label: String(localized: .characterDetailOriginLabel),
                        // El lugar desconocido se dice como los demás valores
                        // desconocidos de la ficha, en el idioma del usuario, en vez de
                        // colar el "unknown" en minúscula que manda la API
                        value: character.origin ?? String(localized: .characterDetailUnknownPlace),
                        systemImage: "globe"
                    )

                    DetailRow(
                        label: String(localized: .characterDetailLocationLabel),
                        value: character.location ?? String(localized: .characterDetailUnknownPlace),
                        systemImage: "mappin.and.ellipse"
                    )
                }
                .background(
                    .background.secondary,
                    in: .rect(cornerRadius: 18)
                )
            }
        }
    }

    // MARK: - Episodes

    @ViewBuilder
    private var episodes: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text(.characterDetailEpisodesTitle)
                    .font(.title2.bold())

                if !viewModel.episodes.isEmpty {
                    Text(.characterDetailEpisodesCountBadge(viewModel.episodes.count))
                        .font(.subheadline.weight(.semibold))
                        // En primario y no en verde, por lo mismo que el badge de
                        // estado: verde sobre verde claro se queda en 2:1 en modo claro
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            .green.opacity(0.12),
                            in: .capsule
                        )
                }
            }

            switch viewModel.state {
            case .idle, .loading:
                episodeSkeleton

            case .loaded, .empty:
                if viewModel.episodes.isEmpty {
                    Text(.characterDetailNoEpisodes)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                } else {
                    episodeList
                }

            case .failed(let error):
                episodesUnavailable(error)
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
        .background(
            .background.secondary,
            in: .rect(cornerRadius: 18)
        )
    }

    private var episodeSkeleton: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<4, id: \.self) { index in
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
        .background(
            .background.secondary,
            in: .rect(cornerRadius: 18)
        )
        .redacted(reason: .placeholder)
    }

    private func episodesUnavailable(_ error: AppError) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(
                error.title,
                systemImage: error.systemImage
            )
            .font(.subheadline.weight(.semibold))

            Text(error.message)
                .font(.footnote)
                .foregroundStyle(.secondary)

            Button(.characterDetailRetryButton) { loadAttempt += 1 }
            .buttonStyle(.bordered)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            .background.secondary,
            in: .rect(cornerRadius: 18)
        )
    }

    private func errorView(_ error: AppError) -> some View {
        ContentUnavailableView {
            Label(
                error.title,
                systemImage: error.systemImage
            )
        } description: {
            Text(error.message)
        } actions: {
            Button(.characterDetailRetryButton) { loadAttempt += 1 }
            .buttonStyle(.borderedProminent)
        }
    }
}

// Una fila de dato: etiqueta a la izquierda, valor a la derecha.
// Con ViewThatFits porque en cuanto se sube el tamaño de letra "Location" y "Citadel of
// Ricks" dejan de caber en la misma línea; antes que recortar el valor, la fila se parte
// en dos. Es lo que hace que la pantalla siga leyéndose con tamaños de accesibilidad.
private struct DetailRow: View {
    let label: String
    let value: String
    let systemImage: String
    // El separador va dentro de la fila y no entre filas en el padre porque su sangría
    // depende del tamaño del icono, que solo la fila conoce
    var showsDivider = true

    // La caja del icono crece con la letra. Fija en 28 pt, desde el tamaño AX2 el
    // símbolo se salía de su fondo y pisaba el hueco con la etiqueta.
    @ScaledMetric(relativeTo: .subheadline) private var iconSize: CGFloat = 28
    private let iconSpacing: CGFloat = 12

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsDivider {
                Divider()
                    .padding(.leading, 16 + iconSize + iconSpacing)
            }

            ViewThatFits(in: .horizontal) {
                horizontalLayout

                verticalLayout
            }
            // A todo el ancho y pegada a la izquierda: la variante vertical es más
            // estrecha que la fila, y sin esto el contenedor la centraba y los iconos
            // quedaban descolgados de la fila de arriba
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var horizontalLayout: some View {
        HStack(alignment: .firstTextBaseline, spacing: iconSpacing) {
            icon

            labelText

            Spacer(minLength: 16)

            valueText
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var verticalLayout: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: iconSpacing) {
                icon
                labelText
            }

            valueText
                .padding(.leading, iconSize + iconSpacing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // El icono es decoración: la etiqueta ya dice de qué va la fila, así que puede ir
    // en verde sin que el contraste importe
    private var icon: some View {
        Image(systemName: systemImage)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.green)
            .frame(width: iconSize, height: iconSize)
            .background(
                .green.opacity(0.1),
                in: .rect(cornerRadius: 8)
            )
    }

    private var labelText: some View {
        Text(label)
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }

    private var valueText: some View {
        Text(value)
            .font(.subheadline.weight(.medium))
            .fixedSize(horizontal: false, vertical: true)
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
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 12))

        layout {
            Text(episode.code)
                .font(.caption.monospaced().weight(.semibold))
                // En primario, no en verde: el verde sobre su propio tinte no llega al
                // contraste que pide un texto de 12 pt (queda en 1.9:1 en modo claro)
                .foregroundStyle(.primary)
                // Un código no se parte: antes que doblarse cede la línea al título
                .fixedSize()
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    .green.opacity(0.1),
                    in: .rect(cornerRadius: 10)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(episode.name)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)

                if let airDate = episode.formattedAirDate {
                    Text(airDate)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        // El ancho lo pone la fila y no un Spacer: en la variante vertical un Spacer
        // empujaría hacia abajo en vez de hacia la derecha
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
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
