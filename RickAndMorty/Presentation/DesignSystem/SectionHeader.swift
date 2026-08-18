import SwiftUI

// El título de una sección dentro de una pantalla, con un acompañante opcional a la
// derecha —un recuento, un estado, lo que la sección tenga que decir de sí misma.
//
// El acompañante entra por `@ViewBuilder` y no como un texto porque quien decide si hay
// algo que enseñar es la pantalla: en la ficha, el recuento de episodios solo aparece
// cuando han llegado, y ese `if` se escribe dentro del bloque sin que este componente
// tenga que saber nada.
struct SectionHeader<Accessory: View>: View {
    private let title: LocalizedStringResource
    private let accessory: Accessory

    init(_ title: LocalizedStringResource, @ViewBuilder accessory: () -> Accessory) {
        self.title = title
        self.accessory = accessory()
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.medium) {
            Text(title)
                .font(.sectionTitle)

            accessory
        }
    }
}

extension SectionHeader where Accessory == EmptyView {
    init(_ title: LocalizedStringResource) {
        self.init(title) { EmptyView() }
    }
}

#Preview("Section headers") {
    VStack(alignment: .leading, spacing: Theme.Spacing.xLarge) {
        SectionHeader(.characterDetailInformationTitle)

        SectionHeader(.characterDetailEpisodesTitle) {
            Text(.characterDetailEpisodesCountBadge(12))
                .font(.labelStrong)
                .tintedChip(in: .capsule)
        }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(Theme.Layout.screenMargin)
}
