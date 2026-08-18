import SwiftUI

// Cómo se enseña un fallo, en las dos formas que necesita la app.
//
// La diferencia entre las dos no es de estilo, es de a qué afecta el fallo. Si no hay
// nada que enseñar, el error *es* la pantalla y ocupa el sitio del contenido
// (`ErrorStateView`). Si lo que ya está en pantalla sigue siendo válido —una lista
// cargada a la que le falta la página siguiente, una ficha a la que le faltan los
// episodios—, el error es una pieza más dentro del contenido y no se lleva por delante
// lo que el usuario ya estaba mirando (`InlineErrorView`).
//
// El texto del botón lo pone quien llama y no el componente: «Try again» está en el
// catálogo una vez por pantalla, y cada una puede decirlo a su manera sin que esto tenga
// que saber desde dónde lo están usando.

// El fallo cuando no hay nada más que enseñar.
// Encima de `ContentUnavailableView` porque es la vista que iOS usa para esto en todas
// sus apps: el usuario ya sabe leerla, y hereda gratis su tipografía, sus márgenes y su
// comportamiento con tamaños grandes.
struct ErrorStateView: View {
    let error: AppError
    let retryTitle: LocalizedStringResource
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(error.title, systemImage: error.systemImage)
        } description: {
            Text(error.message)
        } actions: {
            Button(retryTitle, action: retry)
                .buttonStyle(.borderedProminent)
        }
    }
}

// El fallo de una parte, dentro del contenido que sigue siendo bueno.
// En una tarjeta y alineado a la izquierda, como el resto de bloques de la app: es lo que
// hace que se lea como «esta parte no ha llegado» y no como «la pantalla ha fallado».
struct InlineErrorView: View {
    let error: AppError
    let retryTitle: LocalizedStringResource
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            Label(error.title, systemImage: error.systemImage)
                .font(.labelStrong)

            Text(error.message)
                .font(.message)
                .foregroundStyle(.secondary)

            Button(retryTitle, action: retry)
                .buttonStyle(.bordered)
                .padding(.top, Theme.Spacing.xSmall)
        }
        // El texto se parte solo con tamaños grandes; sin esto la tarjeta se encogería al
        // ancho de su línea más larga.
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.large)
        .cardSurface()
    }
}

#Preview("Error state") {
    ErrorStateView(error: .offline, retryTitle: .characterListRetryButton) {}
}

#Preview("Inline error") {
    InlineErrorView(error: .server(statusCode: 503), retryTitle: .characterDetailRetryButton) {}
        .padding(Theme.Layout.screenMargin)
}
