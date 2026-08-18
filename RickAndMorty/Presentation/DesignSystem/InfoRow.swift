import SwiftUI

// Una fila de dato: etiqueta a la izquierda, valor a la derecha.
//
// Con `ViewThatFits` porque en cuanto se sube el tamaño de letra «Location» y «Citadel of
// Ricks» dejan de caber en la misma línea; antes que recortar el valor, la fila se parte
// en dos. Es lo que hace que la pantalla siga leyéndose con tamaños de accesibilidad.
//
// Vive en el sistema de diseño y no dentro de la ficha porque es la pieza que necesita
// cualquier pantalla que enseñe datos de algo: la siguiente —una localización, un
// episodio— se monta con esto y no vuelve a resolver el mismo problema de layout.
struct InfoRow: View {
    let label: String
    let value: String
    let systemImage: String
    // El separador va dentro de la fila y no entre filas en el padre porque su sangría
    // depende del tamaño del icono, que solo la fila conoce.
    var showsDivider = true

    // La misma base y el mismo estilo de referencia que usa `IconTile` para su caja: un
    // `@ScaledMetric` solo vive dentro de la vista que lo declara, así que la fila declara
    // el suyo para sangrar el separador y la variante apilada. Al partir de lo mismo,
    // escalan a la vez.
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
            // A todo el ancho y pegada a la izquierda: la variante vertical es más
            // estrecha que la fila, y sin esto el contenedor la centraba y los iconos
            // quedaban descolgados de la fila de arriba.
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
