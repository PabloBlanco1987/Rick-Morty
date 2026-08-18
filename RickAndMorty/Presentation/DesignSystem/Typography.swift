import SwiftUI

// Los tokens de texto de la app.
//
// Todos son alias sobre los *text styles* del sistema —`.headline`, `.subheadline`,
// `.caption`— y ninguno es un tamaño en puntos. Esa es la condición para que el Dynamic
// Type siga funcionando hasta AX5 sin tocar nada: un `.system(size: 17)` se queda
// clavado en 17 aunque el usuario haya pedido 43, y la pantalla que hoy se lee entera
// deja de leerse. Aquí un token solo elige *papel*; el tamaño lo sigue eligiendo el
// usuario en los ajustes.
//
// Van en `extension Font` y no dentro de `Theme` porque así el sitio donde se usan queda
// igual de corto que con la API del sistema —`.font(.cardTitle)` al lado de
// `.font(.headline)`— y porque el tipo de destino ya desambigua: no hace falta prefijo
// para saber que eso es una fuente. Los tokens numéricos no tienen esa suerte —un
// `CGFloat` es un `CGFloat` sea un hueco o un radio— y por eso viven con su nombre y
// apellido en `Theme`.
extension Font {
    // El nombre del personaje en la ficha, que es el título de la pantalla.
    static let screenTitle: Font = .largeTitle.bold()
    // «Information», «Episodes»: lo que abre una sección dentro de una pantalla.
    static let sectionTitle: Font = .title2.bold()
    // El nombre en una celda del listado.
    static let cardTitle: Font = .headline

    // Los tres pesos del texto corriente, que es donde estaba casi toda la variedad.
    // Se distinguen por énfasis y no por sitio: el mismo `.label` vale para la especie de
    // una celda, la etiqueta de una fila o el nombre de un episodio, y así no hace falta
    // un token nuevo cada vez que aparece una pantalla.
    static let label: Font = .subheadline
    // El dato de una fila, y los símbolos que lo acompañan.
    static let labelEmphasis: Font = .subheadline.weight(.medium)
    // El titular de un aviso o de un error, y el recuento de episodios.
    static let labelStrong: Font = .subheadline.weight(.semibold)

    // El cuerpo de un aviso: qué ha pasado y qué se puede hacer.
    static let message: Font = .footnote
    // Lo que acompaña a un dato sin ser el dato: la fecha de emisión de un episodio.
    static let metadata: Font = .caption

    // El texto de un chip.
    static let chipLabel: Font = .caption.weight(.medium)
    // El código de un episodio. Monoespaciada porque «S01E01» y «S03E10» son el mismo
    // dato con distinto contenido: alineados, la temporada se lee de un vistazo en toda
    // la columna.
    static let chipCode: Font = .caption.monospaced().weight(.semibold)

    // La silueta gris del hueco de una imagen mientras no ha llegado.
    static let placeholderIcon: Font = .largeTitle
}
