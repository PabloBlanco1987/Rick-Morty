import SwiftUI

// Las decisiones de estilo de la app, en un sitio.
//
// Antes de esto cada vista elegía lo suyo, y el recuento lo decía todo: seis radios
// distintos para cuatro formas, tres opacidades de verde que a ojo son la misma, y un
// margen de pantalla que era 16 en el listado y 20 en el detalle. Nada de eso se ve
// como un fallo, pero es exactamente lo que hace que una app parezca hecha a trozos.
//
// El sistema es deliberadamente pequeño: solo tokens que el proyecto ya estaba
// decidiendo a mano. Lo que ya resuelve la plataforma —`Form`, `ContentUnavailableView`,
// los estilos de botón, los materiales, los colores semánticos— se queda como está;
// un sistema de diseño que pelea con las convenciones de iOS cuesta más de lo que da.
//
// Tres reglas más lo gobiernan, y están donde se aplican:
//   · ninguna vista escribe un literal de estilo (si hace falta uno nuevo, es un token);
//   · los tokens de texto son alias sobre *text styles*, nunca tamaños en puntos, que es
//     lo que mantiene intacto el Dynamic Type —ver `Typography.swift`;
//   · la escala manda en las distancias *entre* elementos; los tamaños intrínsecos de un
//     componente —el punto del badge, el lado de la caja del icono— viven con él, porque
//     crecen con la letra y no significan nada fuera de ahí.
enum Theme {
    // Escala de 4, con un escalón de 2 para lo que va casi pegado.
    //
    // Los nombres son de talla y no de propósito a propósito: un espaciado no sabe si
    // separa un título de su cuerpo o dos celdas, y bautizarlo `sectionGap` obliga a
    // inventar un nombre nuevo la próxima vez que haga falta el mismo hueco en otro
    // sitio. Los tokens con nombre de propósito son los de `Layout`, que sí lo tienen.
    enum Spacing {
        // Entre dos líneas del mismo bloque: un título y su fecha, un titular y su
        // mensaje. Menos que esto ya es interlineado, no separación.
        static let xxSmall: CGFloat = 2
        static let xSmall: CGFloat = 4
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
        static let large: CGFloat = 16
        static let xLarge: CGFloat = 24
        // Entre las secciones de una pantalla, que es la única separación que tiene que
        // leerse como «aquí empieza otra cosa» sin necesidad de una línea.
        static let xxLarge: CGFloat = 32
    }

    // Tres radios para tres papeles, y no seis para cuatro formas.
    //
    // El tamaño del radio es lo que dice de qué tamaño es la pieza: cuanto más grande la
    // superficie, más grande la curva. Con 14 en el aviso, 16 en la celda y 18 en el
    // bloque de datos, tres piezas del mismo tamaño se curvaban distinto sin que hubiera
    // ninguna razón detrás.
    enum Radius {
        // Lo pequeño que envuelve texto o un icono: chips, códigos de episodio, cajas de
        // símbolo.
        static let chip: CGFloat = 10
        // Todo lo que es una superficie de contenido: celdas, bloques, avisos.
        static let card: CGFloat = 16
        // La imagen grande del detalle, que es la única pieza de su tamaño.
        static let hero: CGFloat = 20
    }

    // Las medidas que sí tienen nombre de propósito, porque solo significan algo en su
    // sitio: un ancho máximo no es «grande», es «lo que mide un avatar de la API».
    enum Layout {
        // El mismo margen en las dos pantallas. Cuando el listado usaba 16 y el detalle
        // 20, la diferencia no se veía en ninguna captura suelta y sí se notaba al
        // navegar entre las dos: el contenido daba un salto lateral de cuatro puntos.
        static let screenMargin = Spacing.large
        static let gridSpacing = Spacing.large

        // Con tamaños de accesibilidad el nombre necesita el ancho entero, así que el
        // grid pasa a una columna antes que recortar texto.
        static let gridMinimumColumnWidth: CGFloat = 150
        static let accessibilityGridMinimumColumnWidth: CGFloat = 280

        // Los avatares de la API son de 300 px: en un iPad a pantalla completa, el ancho
        // entero serían mil puntos de imagen estirada. En un iPhone el tope no llega a
        // aplicarse.
        static let heroImageMaxWidth: CGFloat = 360
        // Un aviso de dos líneas a lo ancho de un iPad se lee peor que centrado y
        // acotado; es el ancho de columna de lectura de toda la vida.
        static let noticeMaxWidth: CGFloat = 560

        // Las celdas que caben en una pantalla larga. Menos dejaría un hueco debajo que
        // delataría que aún no hay nada.
        static let skeletonCardCount = 8
        static let skeletonEpisodeCount = 4
    }

    // El color de acento y su relleno.
    //
    // Es una constante de código y no un color del catálogo de recursos: `.green` ya se
    // adapta a claro y oscuro y al modo de contraste alto, y un color propio obligaría a
    // redefinir esas variantes a mano para acabar en el mismo verde. El día que haya
    // marca se cambia esta línea —o pasa a ser `Color("Accent")`— y no se toca una sola
    // vista.
    enum Tint {
        static let accent: Color = .green

        // Una sola opacidad para todos los rellenos tintados. Había 0,10, 0,12 y 0,15
        // repartidas entre el chip del recuento, el código de episodio y el badge de
        // estado: tres valores que a ojo son el mismo y que solo garantizaban que el
        // cuarto sitio tuviera un cuarto valor.
        static let fillOpacity: Double = 0.12

        static func fill(_ color: Color) -> Color {
            color.opacity(fillOpacity)
        }

        static var accentFill: Color {
            fill(accent)
        }
    }

    // Las dos únicas animaciones de la app, y la regla que las gobierna.
    //
    // Con «reducir movimiento» no se mueve nada, ni siquiera un desvanecido: quien pide
    // que no se mueva la pantalla no está pidiendo que se mueva más despacio. La regla
    // estaba escrita a mano en los dos sitios que animan; devolver `Animation?` la deja
    // escrita una vez y hace imposible olvidarla en el tercero, porque para animar hay
    // que pasar por aquí.
    enum Motion {
        // La entrada de una imagen que ha habido que ir a buscar.
        static func fade(reduceMotion: Bool) -> Animation? {
            reduceMotion ? nil : .easeOut(duration: 0.2)
        }

        // La aparición y la salida del aviso de refresco fallido.
        static func notice(reduceMotion: Bool) -> Animation? {
            reduceMotion ? nil : .easeInOut(duration: 0.25)
        }
    }
}
