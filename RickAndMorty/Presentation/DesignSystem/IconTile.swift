import SwiftUI

// La caja de un símbolo, tintada, para poner delante de un dato.
//
// El símbolo es decoración: la etiqueta que va al lado ya dice de qué es la fila, así que
// el icono puede ir en el color de acento sin que su contraste importe. Si algún día un
// icono fuera el único portador de un dato, dejaría de poder ir así —y eso es justo lo
// que este comentario tiene que recordar.
struct IconTile: View {
    let systemImage: String
    var tint: Color = Theme.Tint.accent

    // El lado crece con la letra. Fijo en 28 pt, desde el tamaño AX2 el símbolo se salía
    // de su fondo y pisaba el hueco de la etiqueta.
    @ScaledMetric(relativeTo: .subheadline) private var side: CGFloat = IconTile.baseSide

    // La medida sin escalar, para quien tenga que alinear algo con la caja: `InfoRow`
    // sangra su separador y su variante apilada con este mismo número. Un `@ScaledMetric`
    // solo existe dentro de la vista que lo declara, así que la fila declara el suyo con
    // esta misma base y `relativeTo:` en el mismo estilo; escalan igual porque parten de
    // lo mismo.
    static let baseSide: CGFloat = 28

    var body: some View {
        Image(systemName: systemImage)
            .font(.labelEmphasis)
            .foregroundStyle(tint)
            .frame(width: side, height: side)
            .background(Theme.Tint.fill(tint), in: .rect(cornerRadius: Theme.Radius.chip))
    }
}

#Preview("Icon tiles") {
    HStack(spacing: Theme.Spacing.medium) {
        IconTile(systemImage: "sparkles")
        IconTile(systemImage: "globe")
        IconTile(systemImage: "mappin.and.ellipse")
    }
    .padding(Theme.Layout.screenMargin)
}
