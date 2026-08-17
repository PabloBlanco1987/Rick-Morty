import SwiftUI

// La celda del listado.
// Equatable no es decoración: con .equatable() SwiftUI compara la celda entera contra
// la anterior y se salta la reconstrucción del cuerpo si el personaje no ha cambiado.
// Al añadir una página, lo único que hay que construir son las 20 celdas nuevas; las
// 800 de antes se descartan con una comparación de structs. Se puede hacer porque
// Character es un valor y la celda no guarda nada más: si le colgáramos un closure
// dejaría de ser comparable y la optimización desaparecería sin avisar.
struct CharacterCard: View, Equatable {
    let character: Character

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CachedAsyncImage(url: character.imageURL)
                // Cuadrada: los avatares de la API lo son, y fijar la proporción antes
                // de que llegue la imagen es lo que evita que la fila entera dé un
                // salto de altura cuando cada una aterriza.
                .aspectRatio(1, contentMode: .fit)
                .overlay(alignment: .topTrailing) {
                    CharacterStatusBadge(status: character.status)
                        .padding(12)
                }

            VStack(alignment: .leading, spacing: 6) {
                Text(character.name)
                    .font(.headline)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(character.species)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
        }
        // Estirada hasta la altura de la fila para que dos celdas con nombres de
        // distinto largo no dejen el fondo a media asta
        .frame(maxHeight: .infinity, alignment: .top)
        .background(.background.secondary, in: .rect(cornerRadius: 16))
        .contentShape(.rect(cornerRadius: 16))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier("character-\(character.id)")
    }

    private var accessibilityLabel: String {
        "\(character.name). \(character.species). \(character.status.accessibilityDescription)"
    }
}

// El mismo hueco que ocupa una celda, sin datos.
// Se pinta la forma de verdad y no un rectángulo genérico para que al llegar los
// personajes no cambie nada de sitio: la carga deja de verse como un salto y pasa a
// verse como que el contenido se rellena.
struct CharacterCardSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(.fill.tertiary)
                .aspectRatio(1, contentMode: .fit)
                .overlay(alignment: .topTrailing) {
                    CharacterStatusBadge(status: .unknown)
                        .padding(12)
                }

            VStack(alignment: .leading, spacing: 6) {
                Text("Character name")
                    .font(.headline)

                Text("Species")
                    .font(.subheadline)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(.background.secondary, in: .rect(cornerRadius: 16))
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
