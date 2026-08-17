import SwiftUI

// El estado del personaje, con color y con texto.
// Solo con el color no valdría: quien no distingue el verde del rojo —que es en torno
// al 8% de los hombres— se quedaría sin el dato, y el color tampoco sobrevive a una
// captura en blanco y negro ni al modo de contraste alto. El color acompaña, no
// informa.
struct CharacterStatusBadge: View {
    let status: Character.Status

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(status.tint)
                .frame(width: 8, height: 8)

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

    // Lo que oye quien usa VoiceOver. Aquí sí conviene la frase entera: "Alive" suelto,
    // después de un nombre y una especie, se entiende regular.
    var accessibilityDescription: String {
        switch self {
        case .alive: String(localized: .characterStatusAlive)
        case .dead: String(localized: .characterStatusDead)
        case .unknown: String(localized: .characterStatusUnknownAccessibilityLabel)
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
