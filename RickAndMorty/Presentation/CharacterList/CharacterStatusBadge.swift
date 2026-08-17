import SwiftUI

// El estado del personaje, con color y con texto.
// Solo con el color no valdría: quien no distingue el verde del rojo —que es en torno
// al 8% de los hombres— se quedaría sin el dato, y el color tampoco sobrevive a una
// captura en blanco y negro ni al modo de contraste alto. El color acompaña, no
// informa.
struct CharacterStatusBadge: View {
    let status: Character.Status

    // El punto y su hueco crecen con el texto: con tamaños de accesibilidad la letra
    // llega a los 43 pt y un punto fijo de 8 se quedaba en una mota al lado
    @ScaledMetric(relativeTo: .caption) private var dotSize: CGFloat = 8
    @ScaledMetric(relativeTo: .caption) private var spacing: CGFloat = 6

    var body: some View {
        HStack(spacing: spacing) {
            Circle()
                .fill(status.tint)
                .frame(width: dotSize, height: dotSize)

            Text(status.displayName)
                .font(.caption.weight(.medium))
                // El texto en color primario y no en el del estado: verde sobre verde
                // claro no llega al contraste 4.5:1 que pide la WCAG, y el color ya lo
                // está dando el punto.
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background {
            Capsule()
                .fill(.background)
                .overlay {
                    Capsule()
                        .fill(status.tint.opacity(0.15))
                }
        }
    }
}

extension Character.Status {
    // El texto y el color viven en presentación: el dominio no sabe de colores ni de
    // idiomas, y así el mismo caso se puede pintar distinto en el detalle sin tocarlo.
    var displayName: String {
        switch self {
        case .alive: String(localized: .characterStatusAlive)
        case .dead: String(localized: .characterStatusDead)
        case .unknown: String(localized: .characterStatusUnknown)
        }
    }

    var tint: Color {
        switch self {
        case .alive: .green
        case .dead: .red
        case .unknown: .gray
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 12) {
        ForEach(Character.Status.allCases, id: \.self) { status in
            CharacterStatusBadge(status: status)
        }
    }
    .padding()
}
