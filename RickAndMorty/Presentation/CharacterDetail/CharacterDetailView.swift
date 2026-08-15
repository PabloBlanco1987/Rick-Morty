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

    @MainActor
    init(character: Character, fetchCharacterDetail: FetchCharacterDetailUseCase) {
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
            .task { await viewModel.onAppear() }
    }

    @ViewBuilder
    private var content: some View {
        // Sin nada que enseñar, el fallo se lleva la pantalla entera. Con la cabecera ya
        // puesta, en cambio, lo que falla es solo la lista de episodios y se cuenta ahí
        // abajo: tirar un personaje que ya está en pantalla por un episodio que no ha
        // llegado sería cambiar información por un mensaje de error.
        if case .failed(let error) = viewModel.state, !viewModel.hasContentOnScreen {
            errorView(error)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
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

    // MARK: - Cabecera

    @ViewBuilder
    private var header: some View {
        if let character = viewModel.character {
            VStack(alignment: .leading, spacing: 16) {
                CachedAsyncImage(url: character.imageURL)
                    .aspectRatio(1, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .clipShape(.rect(cornerRadius: 20))
                    // Decorativa: el nombre y la especie ya están escritos justo debajo,
                    // así que para VoiceOver la imagen no añade nada y sí una parada más
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 10) {
                    Text(character.name)
                        .font(.largeTitle.bold())
                        .fixedSize(horizontal: false, vertical: true)

                    CharacterStatusBadge(status: character.status)
                }
            }
        }
    }

    // MARK: - Datos

    @ViewBuilder
    private var facts: some View {
        if let character = viewModel.character {
            VStack(alignment: .leading, spacing: 0) {
                DetailRow(label: "Species", value: character.species)
                // El tipo solo aparece cuando lo hay: una fila con un guion es una fila
                // que se lee, se escucha y ocupa sitio para no decir nada
                if let type = character.type {
                    Divider()
                    DetailRow(label: "Type", value: type)
                }
                Divider()
                DetailRow(label: "Gender", value: character.gender.displayName)
                Divider()
                DetailRow(label: "Origin", value: character.origin)
                Divider()
                DetailRow(label: "Location", value: character.location)
            }
            .padding(.vertical, 4)
            .background(.background.secondary, in: .rect(cornerRadius: 16))
        }
    }

    // MARK: - Episodios

    @ViewBuilder
    private var episodes: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Episodes")
                .font(.title2.bold())

            switch viewModel.state {
            case .idle, .loading:
                episodeSkeleton
            case .loaded, .empty:
                if viewModel.episodes.isEmpty {
                    Text("This character doesn't appear in any episode.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
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
            ForEach(Array(viewModel.episodes.enumerated()), id: \.element.id) { index, episode in
                if index > 0 { Divider() }
                EpisodeRow(episode: episode)
            }
        }
        .background(.background.secondary, in: .rect(cornerRadius: 16))
    }

    private var episodeSkeleton: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<4, id: \.self) { index in
                if index > 0 { Divider() }
                EpisodeRow(
                    episode: Episode(id: index, name: "Episode title", code: "S01E01", airDate: nil)
                )
            }
        }
        .background(.background.secondary, in: .rect(cornerRadius: 16))
        .redacted(reason: .placeholder)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading episodes")
    }

    // El fallo de esta sección se cuenta aquí dentro y con su propio botón: es la misma
    // idea que el pie del listado, un trozo de la pantalla que se ha caído y no la
    // pantalla entera.
    private func episodesUnavailable(_ error: AppError) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(error.title, systemImage: error.systemImage)
                .font(.subheadline.weight(.semibold))
            Text(error.message)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button("Try again") {
                Task { await viewModel.retry() }
            }
            .buttonStyle(.bordered)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.background.secondary, in: .rect(cornerRadius: 16))
    }

    private func errorView(_ error: AppError) -> some View {
        ContentUnavailableView {
            Label(error.title, systemImage: error.systemImage)
        } description: {
            Text(error.message)
        } actions: {
            Button("Try again") {
                Task { await viewModel.retry() }
            }
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

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                labelText
                Spacer(minLength: 16)
                valueText
                    .multilineTextAlignment(.trailing)
            }

            VStack(alignment: .leading, spacing: 4) {
                labelText
                valueText
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        // Una parada de VoiceOver por fila, y leída como frase: "Species, Human"
        .accessibilityElement(children: .combine)
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

private struct EpisodeRow: View {
    let episode: Episode

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            // Ancho fijo y monoespaciada para que los códigos queden en columna: en una
            // lista de cincuenta episodios, alinearlos es la diferencia entre poder
            // buscar con la vista y tener que leerlos todos
            Text(episode.code)
                .font(.caption.monospaced().weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(minWidth: 52, alignment: .leading)

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

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    // Se dice "Season 1, episode 1" y no "S01E01", que VoiceOver deletrearía
    private var accessibilityLabel: String {
        [episode.name, episode.spokenCode, episode.formattedAirDate]
            .compactMap(\.self)
            .joined(separator: ". ")
    }
}

extension Episode {
    // El dominio guarda una Date y presentación decide cómo se escribe, así que la fecha
    // sale en el formato del dispositivo: "2 dic 2013" en España y "Dec 2, 2013" en
    // Estados Unidos, sin que el modelo sepa nada de locales.
    var formattedAirDate: String? {
        airDate?.formatted(.dateTime.day().month(.abbreviated).year())
    }

    // "S01E01" se lee de un vistazo pero VoiceOver lo deletrea letra a letra, así que
    // para quien escucha se convierte en la frase que significa.
    var spokenCode: String {
        let numbers = code
            .dropFirst()
            .split(separator: "E")
            .compactMap { Int($0) }

        guard numbers.count == 2 else { return code }
        return "Season \(numbers[0]), episode \(numbers[1])"
    }
}

extension Character.Gender {
    var displayName: String {
        switch self {
        case .female: "Female"
        case .male: "Male"
        case .genderless: "Genderless"
        case .unknown: "Unknown"
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
