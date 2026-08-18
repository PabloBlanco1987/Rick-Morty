import CoreGraphics
import SwiftUI

// Espera creciente entre intentos, mientras la celda siga en pantalla.
//
// Son dos capas de reintento con dos trabajos distintos, y conviene tenerlo claro para
// que no parezcan la misma cosa dos veces. ImageCache reintenta enseguida —cientos de
// milisegundos— el tropiezo de una petición, y lo hace una vez para todas las celdas
// que esperaban esa descarga. Esto de aquí cubre el mal rato de segundos: .task no se
// dispara sola una segunda vez, así que sin esto un servidor caído durante cinco
// segundos deja ese hueco en gris hasta que la celda salga y vuelva a entrar. Por eso
// empieza donde termina la otra, en segundos, y está acotado: si el fallo no es
// pasajero, insistir es gastar batería para enseñar lo mismo.
//
// Fuera del tipo porque CachedAsyncImage es genérico y un genérico no admite
// propiedades estáticas almacenadas.
private let imageRetryDelays: [Duration] = [
    .seconds(1),
    .seconds(3),
    .seconds(8),
]

// La vista de consumo de ImageCache.
// No usa AsyncImage de SwiftUI a propósito: AsyncImage no reduce la imagen al tamaño
// de la celda, no guarda nada entre apariciones —al volver hacia atrás en el scroll
// vuelve a descargar— y no comparte la petición entre dos vistas que piden la misma
// URL. En un grid de 826 avatares esas tres cosas son justo las que se notan.
struct CachedAsyncImage<Placeholder: View>: View {
    private let url: URL?
    private let placeholder: Placeholder

    @Environment(\.imageCache) private var cache
    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var image: CGImage?
    @State private var pointSize: CGSize = .zero

    // Empieza en true a propósito: fuera de un ScrollView —una preview, un test— nadie
    // avisa de la visibilidad, y ahí lo correcto es cargar igual
    @State private var isOnScreen = true

    init(url: URL?, @ViewBuilder placeholder: () -> Placeholder) {
        self.url = url
        self.placeholder = placeholder()
    }

    var body: some View {
        ZStack {
            // El placeholder no se quita del árbol, solo se apaga: así el hueco de la
            // imagen tiene tamaño desde el primer ciclo de layout y las celdas no dan
            // el salto de altura que se ve cuando cada imagen llega.
            placeholder
                .opacity(image == nil ? 1 : 0)

            if let image {
                Image(decorative: image, scale: displayScale, orientation: .up)
                    .resizable()
                    .scaledToFill()
            }
        }
        .clipped()
        .onGeometryChange(for: CGSize.self) { proxy in
            // Redondeado a puntos enteros para que medio punto de diferencia en el
            // layout no dispare otra decodificación
            CGSize(width: proxy.size.width.rounded(.up), height: proxy.size.height.rounded(.up))
        } action: { pointSize = $0 }
        // La visibilidad de verdad, que no es lo mismo que estar viva: LazyVGrid crea
        // las celdas según hacen falta pero no las destruye al pasar de largo, así que
        // .task por sí sola no se cancela nunca y una bajada rápida deja cientos de
        // descargas vivas de celdas que quedaron diez pantallas atrás. El umbral es
        // bajo para que cuente como visible en cuanto asoma un poco.
        .onScrollVisibilityChange(threshold: 0.01) { isOnScreen = $0 }
        // Con id: la carga se cancela y se rearranca sola cuando cambia algo de lo que
        // define la petición, sin que haya que acordarse de limpiar nada
        .task(id: Request(url: url, size: pointSize, isOnScreen: isOnScreen)) { await load() }
    }

    // Identifica lo que hay que cargar. El tamaño entra porque la imagen se decodifica
    // a la medida de la celda: si la celda cambia de tamaño, lo cargado ya no vale. Y
    // la visibilidad entra porque salir de pantalla tiene que cancelar la descarga, y
    // volver a entrar tiene que rearrancarla.
    private struct Request: Equatable {
        let url: URL?
        let size: CGSize
        let isOnScreen: Bool
    }

    private func load() async {
        // Sin URL —la API manda alguna vacía— no hay imagen que enseñar
        guard let url else {
            image = nil
            return
        }

        // Fuera de pantalla, o antes del primer ciclo de layout, no hay nada que pedir.
        // Aquí no se borra lo que ya haya cargado: la celda volverá, y cuando vuelva
        // tiene que aparecer entera, no vacía.
        guard isOnScreen, pointSize.width > 0, pointSize.height > 0 else { return }

        for attempt in 0...imageRetryDelays.count {
            if attempt > 0 {
                do {
                    try await Task.sleep(for: imageRetryDelays[attempt - 1])
                } catch {
                    // Han cancelado la espera: la celda se va, no hay a quién
                    // enseñarle nada
                    return
                }
            }

            do {
                let loaded = try await cache.image(for: url, size: pointSize, scale: displayScale)
                // Solo se funde lo que ha habido que ir a buscar. Lo que ya estaba en
                // memoria aparece de golpe: al volver hacia atrás en el scroll un
                // fundido se lee como un parpadeo, no como una entrada.
                let shouldFade = loaded.origin != .memory && !reduceMotion
                withAnimation(shouldFade ? .easeOut(duration: 0.2) : nil) {
                    image = loaded.image
                }
                return
            } catch {
                // Si a quien han cancelado es a esta celda, se está yendo de la
                // pantalla y ya no hay nada que reintentar
                if Task.isCancelled { return }
                // Y solo se insiste en lo que puede arreglarse esperando. Un 404 va a
                // seguir siendo un 404 dentro de ocho segundos, y unos bytes que no
                // decodifican tampoco van a mejorar: repetir eso son peticiones —y
                // fichas del limitador— gastadas en una imagen que no va a llegar,
                // multiplicadas por cada celda que la tenga.
                guard error.isRetryable else { return }
            }
        }

        // Se agotaron los intentos: se deja el placeholder. En un grid, una celda con
        // un icono de error cada dos es más ruido que información, y el personaje
        // —que es el contenido— sigue ahí con su nombre y su estado.
        //
        // A partir de aquí ese hueco no se rellena hasta que el usuario lo saque de
        // pantalla y lo vuelva a meter. Se deja así a sabiendas: la alternativa buena
        // —que reintentar la lista reintente también las imágenes que fallaron— necesita
        // una señal de reintento que baje desde el view model, y entraría como un valor
        // de entorno que formara parte de la identidad de esta tarea, de modo que
        // subirlo la volviera a disparar en todas las celdas a la vez. Ver README,
        // "Límites conocidos".
        //
        // No se toca `image`: si la celda ya tenía una imagen y la recarga ha fallado,
        // enseñar la que hay es mejor que vaciar el hueco.
    }
}

extension CachedAsyncImage where Placeholder == ImagePlaceholder {
    init(url: URL?) {
        self.init(url: url) { ImagePlaceholder() }
    }
}

// Hueco de imagen neutro: ni spinner ni icono de error.
// Un spinner por celda en un grid es un campo de cosas girando, y para algo que tarda
// lo que tarda una imagen pequeña la espera se lee mejor con un hueco quieto.
struct ImagePlaceholder: View {
    var body: some View {
        Rectangle()
            .fill(.fill.tertiary)
            .overlay {
                Image(systemName: "person.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.tertiary)
            }
    }
}

extension EnvironmentValues {
    // La caché entra por el entorno y no por AppDependencies: qué tamaño necesita una
    // imagen es una decisión de la capa de presentación, no del dominio, y así una
    // preview o un test pueden meter la suya sin tocar la raíz de composición ni
    // arrastrar la caché por el init de cada vista intermedia.
    @Entry var imageCache: ImageCache = .shared
}

#Preview("Placeholder and loading") {
    HStack(spacing: 16) {
        CachedAsyncImage(url: nil)
            .frame(width: 120, height: 120)
            .clipShape(.rect(cornerRadius: 16))

        CachedAsyncImage(url: URL(string: "https://rickandmortyapi.com/api/character/avatar/1.jpeg"))
            .frame(width: 120, height: 120)
            .clipShape(.rect(cornerRadius: 16))
    }
    .padding()
}
