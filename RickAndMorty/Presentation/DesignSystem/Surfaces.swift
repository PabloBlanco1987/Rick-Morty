import SwiftUI

// Las dos superficies de la app: la tarjeta y el chip.
//
// Son modificadores y no vistas envolventes a propósito. Un `CardView { … }` obliga a
// meter el contenido dentro de otro contenedor y cambia el árbol de vistas —justo lo que
// no interesa en una celda que se compara con `.equatable()` ochocientas veces—, mientras
// que un modificador se aplica al final, se lee en el orden en que se pinta y no añade
// una capa de layout.
extension View {
    // El fondo de todo lo que es una superficie de contenido: la celda del listado, el
    // bloque de datos de la ficha, la lista de episodios, un error en línea.
    //
    // El recorte no es opcional ni sobra donde no hay nada que recortar: el fondo
    // redondeado no recorta por sí solo lo que lleva encima, así que sin él la imagen de
    // una celda —que es un rectángulo— asoma con las esquinas cuadradas por encima de las
    // redondeadas del fondo, y la celda acaba con el borde de arriba distinto al de
    // abajo. Donde no hay nada que se salga, recortar no cuesta nada.
    func cardSurface(cornerRadius: CGFloat = Theme.Radius.card) -> some View {
        self
            .background(.background.secondary, in: .rect(cornerRadius: cornerRadius))
            .clipShape(.rect(cornerRadius: cornerRadius))
            .contentShape(.rect(cornerRadius: cornerRadius))
    }

    // El relleno tintado que llevan los chips: el badge de estado, el recuento de
    // episodios, el código de un episodio.
    //
    // El color del tinte se pasa porque no siempre es el de acento: el badge de estado se
    // tiñe del color de su estado —verde, rojo o gris—, que es justo el dato que está
    // dando. La forma también, porque una píldora y un rectángulo redondeado no dicen lo
    // mismo: la píldora es una etiqueta, el rectángulo es una pieza de la fila.
    //
    // Lo que no se pasa nunca es la opacidad ni el texto en color: el contenido de un chip
    // va siempre en color primario. Un texto verde sobre su propio tinte se queda en 1,9:1
    // en modo claro, muy por debajo del 4,5:1 que pide la WCAG, y el color ya lo está
    // dando el fondo.
    func tintedChip(_ tint: Color = Theme.Tint.accent, in shape: some Shape, opaque: Bool = false) -> some View {
        self
            // El color primario lo pone el chip y no cada sitio que lo usa: es una regla
            // de contraste, no una preferencia, y si se deja a criterio de quien llama
            // acaba habiendo un chip con el texto en su propio tinte. Va por dentro del
            // relleno, así que gana a cualquier `foregroundStyle` de fuera.
            .foregroundStyle(.primary)
            .padding(.horizontal, Theme.Spacing.medium)
            .padding(.vertical, Theme.Spacing.xSmall)
            .background {
                // `opaque` es para los chips que flotan sobre una imagen, que es donde un
                // tinte al 12% dejaría ver la foto por debajo y el chip perdería el
                // contraste con su propio texto. Debajo va el fondo de la app, no un
                // blanco: en modo oscuro el blanco sería un foco.
                if opaque {
                    shape.fill(.background)
                }

                shape.fill(Theme.Tint.fill(tint))
            }
    }
}

#Preview("Surfaces") {
    VStack(alignment: .leading, spacing: Theme.Spacing.xLarge) {
        Text(verbatim: "Card surface")
            .font(.cardTitle)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.medium)
            .cardSurface()

        HStack(spacing: Theme.Spacing.medium) {
            Text(verbatim: "12 episodes")
                .font(.chipLabel)
                .tintedChip(in: .capsule)

            Text(verbatim: "S01E01")
                .font(.chipCode)
                .tintedChip(in: .rect(cornerRadius: Theme.Radius.chip))

            Text(verbatim: "Alive")
                .font(.chipLabel)
                .tintedChip(in: .capsule, opaque: true)
        }
    }
    .padding(Theme.Layout.screenMargin)
}
