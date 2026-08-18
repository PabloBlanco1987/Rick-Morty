import SwiftUI

// El aviso de que un pull to refresh ha fallado y la lista que se ve puede estar vieja.
//
// Es un aviso y no una pantalla de error porque la lista sigue siendo válida: lo que se
// cuenta es que no se ha podido comprobar si ha cambiado, y eso cabe en dos líneas que
// se van solas. Se va a los seis segundos —lo que se tarda en leerlas sin prisa—, al
// tocarlo, o antes si otro refresco vuelve a traer datos, que es lo que hace el view
// model al limpiar `refreshFailure`.
//
// No hay cola porque no hay más de un emisor: si un segundo refresh falla mientras
// este aviso está en pantalla, se queda el que hay, con el error nuevo si es distinto,
// y la cuenta atrás vuelve a empezar solo en ese caso. Un mismo fallo repetido no
// reinicia nada: el aviso ya está diciendo lo que hay.
struct RefreshFailureNotice: View {
    let error: AppError
    let dismiss: () -> Void

    private static let lifetime: Duration = .seconds(6)

    var body: some View {
        // Es un botón entero, y no un texto con una cruz aparte, para que descartarlo
        // sea tocar en cualquier sitio
        Button(action: dismiss) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.medium) {
                Image(systemName: error.systemImage)
                    .font(.labelStrong)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: Theme.Spacing.xxSmall) {
                    Text(error.title)
                        .font(.labelStrong)
                    Text(.characterListRefreshFailedMessage)
                        .font(.message)
                        .foregroundStyle(.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
            .padding(Theme.Spacing.large)
            .frame(maxWidth: Theme.Layout.noticeMaxWidth)
            // El material y el borde son suyos y no de `cardSurface`: este aviso no es una
            // superficie de contenido, es una pieza que flota por encima del listado
            // mientras se lee y se va sola. El desenfoque es lo que lo separa de lo que
            // tiene debajo sin necesidad de una sombra.
            .background(.regularMaterial, in: .rect(cornerRadius: Theme.Radius.card))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.card)
                    .strokeBorder(.separator, lineWidth: 0.5)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("refresh-failed")
        // Con id: si el error cambia mientras el aviso está en pantalla, la cuenta atrás
        // vuelve a empezar; al desaparecer el aviso, SwiftUI cancela la tarea sola
        .task(id: error) {
            do {
                try await Task.sleep(for: Self.lifetime)
            } catch {
                // Cancelada: el aviso ya se ha ido por otro camino
                return
            }
            dismiss()
        }
    }
}

#Preview {
    VStack(spacing: Theme.Spacing.large) {
        RefreshFailureNotice(error: .offline) {}
        RefreshFailureNotice(error: .server(statusCode: 503)) {}
    }
    .padding()
}
