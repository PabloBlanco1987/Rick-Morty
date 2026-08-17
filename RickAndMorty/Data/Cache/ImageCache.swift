import CoreGraphics
import CryptoKit
import Foundation
import ImageIO

// Caché de imágenes de dos niveles con deduplicación de descargas.
//
// Los tres gastos que se cargan un scroll, en orden de impacto:
//
// 1. Decodificar. Un avatar de la API son 300x300 px comprimidos en unos 25 KB, pero
//    el bitmap que sale de decodificarlo ocupa 360 KB, y multiplicado por las celdas
//    que caben en pantalla es lo que acaba en un aviso de memoria. Aquí se decodifica
//    a la medida de la celda y en el momento, no al ir a pintar: el bitmap nunca es
//    mayor que lo que se ve, así que el techo lo pone el layout y no lo que decida
//    mandar el servidor. Con los 300x300 de hoy y celdas de 150 pt para arriba el
//    recorte no llega a aplicarse —ImageIO no amplía—; lo que sí se nota en cada
//    celda es forzar la decodificación aquí, fuera del hilo principal.
// 2. Repetir trabajo. Volver hacia atrás en el scroll no puede costar otra descarga
//    ni otra decodificación: memoria primero, disco después y la red como último
//    recurso.
// 3. Pedir lo mismo dos veces a la vez. En un grid es lo normal, no la excepción, y
//    dos peticiones para la misma URL son dos conexiones y dos decodificaciones para
//    acabar con el mismo bitmap.
//
// Es un actor y no una clase con locks porque el estado que protege —el diccionario
// de descargas en vuelo— se toca desde tantas tareas como celdas haya en pantalla, y
// el aislamiento lo resuelve sin un solo candado a mano.
actor ImageCache {
    // De dónde ha salido la imagen. Lo devuelve porque la vista lo necesita para
    // decidir si funde o no: lo que ya estaba en memoria tiene que aparecer de golpe.
    enum Origin: Sendable {
        case memory
        case disk
        case network
    }

    struct LoadedImage: Sendable {
        let image: CGImage
        let origin: Origin
    }

    // Se inyecta para que los tests no toquen la red. En producción es Self.download.
    typealias DataLoader = @Sendable (URL) async throws(AppError) -> Data

    static let shared = ImageCache()

    private let directory: URL
    private let loader: DataLoader
    private let settleDelay: Duration
    private let memory = NSCache<NSString, Entry>()

    // Todo lo que vaya a la red pasa por aquí: pocas a la vez y la última pedida
    // primero. Es lo que hace que al bajar rápido se pinte lo que se está mirando y no
    // la cola de lo que ya se dejó atrás.
    private let queue: DownloadQueue

    // Descargas en vuelo, por URL. Si dos celdas piden la misma imagen a la vez, la
    // segunda encuentra aquí la tarea de la primera y se queda esperándola en vez de
    // abrir otra conexión. La clave es la URL y no la URL más el tamaño a propósito:
    // lo que no se puede duplicar es la descarga, y los bytes descargados sirven para
    // cualquier tamaño.
    private var inFlight: [URL: Download] = [:]
    private var lastWaiterToken = 0

    // internal para que los tests puedan comprobar que una descarga que ya no
    // interesa a nadie desaparece de verdad, y que una pausa retiene de verdad
    var inFlightCount: Int { inFlight.count }
    var waitingDownloadCount: Int {
        get async { await queue.waitingCount }
    }

    init(
        directory: URL = ImageCache.defaultDirectory,
        // 50 MB de bitmaps. Un avatar de los de hoy decodificado son 360 KB, así que
        // caben unos 145: más de lo que ocupan cuatro pantallas de scroll, que es la
        // distancia a la que un usuario vuelve hacia atrás.
        memoryLimit: Int = 50 * 1024 * 1024,
        // Cuatro a la vez. Más no llega antes —el cuello está en las conexiones y en el
        // ancho de banda, no en cuántas peticiones hayamos soltado— y sí deja al
        // servidor recibiendo ráfagas que se acaban traduciendo en 5xx, que es lo que
        // luego tumba la petición de la página siguiente.
        maxConcurrentDownloads: Int = 4,
        // Lo que tiene que llevar una celda en pantalla antes de que se gaste una
        // petición por ella. En un vistazo rápido las celdas asoman y se van en
        // decenas de milisegundos: pedir esas imágenes es gastar peticiones en lo que
        // nadie ha llegado a ver, y una ráfaga así es la que hace que la API conteste
        // 429 y se lleve por delante también la carga de la página siguiente.
        // No retrasa nada de lo que ya esté en memoria o en disco: eso ni pasa por aquí.
        settleDelay: Duration = .milliseconds(120),
        // El mismo que usa el cliente HTTP: el cupo del servidor es uno para JSON e
        // imágenes, así que el freno tiene que ser el mismo objeto
        limiter: RateLimiter = .shared,
        // nil y no un valor por defecto porque el de producción necesita el limitador de
        // arriba, y un valor por defecto no puede leer otro parámetro
        loader: DataLoader? = nil
    ) {
        self.directory = directory
        self.loader = loader ?? Self.retrying({ (url: URL) async throws(AppError) -> Data in
            try await Self.download(url, through: limiter)
        })
        self.settleDelay = settleDelay
        self.queue = DownloadQueue(limit: maxConcurrentDownloads)
        // NSCache ya se vacía sola cuando el sistema avisa de presión de memoria, así
        // que el límite es un techo, no la única defensa.
        memory.totalCostLimit = memoryLimit
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    // Devuelve la imagen ya decodificada al tamaño en el que se va a pintar.
    // size va en puntos y scale es la escala de la pantalla. La conversión a píxeles
    // se hace aquí y no en la vista porque el tamaño forma parte de la clave de
    // memoria: la misma URL a 110 pt y a 300 pt son dos bitmaps distintos.
    func image(for url: URL, size: CGSize, scale: CGFloat) async throws(AppError) -> LoadedImage {
        let pixelSize = Self.pixelSize(for: size, scale: scale)
        let key = Self.memoryKey(url: url, pixelSize: pixelSize)

        if let entry = memory.object(forKey: key) {
            return LoadedImage(image: entry.image, origin: .memory)
        }

        let fetched = try await fetch(url, priority: .visible)

        // Antes de decodificar, que es la parte cara. Si la celda ya se ha ido de la
        // pantalla no tiene sentido gastar CPU y memoria en un bitmap que nadie va a
        // ver; los bytes ya están guardados en disco, así que no se pierde el trabajo
        // que sí valía.
        if Task.isCancelled { throw .cancelled }

        guard let image = await Self.downsample(fetched.data, to: pixelSize) else {
            // Unos bytes que no son una imagen no pueden quedarse en disco: la descarga
            // los guarda antes de saber si decodifican, y si se quedaran, cada visita
            // siguiente los leería de ahí, fallaría igual y no volvería a bajarlos nunca.
            // Es lo que hace un portal cautivo —el wifi de un hotel que contesta 200 con
            // su página de acceso— y sin esto envenena la caché hasta que el sistema la
            // vacíe. Borrando, el siguiente intento vuelve a la red.
            await Self.removeFile(at: fileURL(for: url))
            throw .decoding
        }

        memory.setObject(Entry(image), forKey: key, cost: image.decodedByteCount)
        return LoadedImage(image: image, origin: fetched.origin)
    }

    // Deja en disco las imágenes de una página que acaba de llegar y aún no se ve, para
    // que cuando el usuario baje hasta ella las celdas aparezcan ya con su imagen en vez
    // de con un hueco que se rellena. Es la sensación de una app que "ya lo tenía".
    //
    // Va en secuencia a propósito: ocupa como mucho un hueco de los cuatro y gasta el
    // cupo del servidor de uno en uno, así que nunca compite con lo que se está mirando.
    // Y va por la misma `fetch` que las celdas, con prioridad baja: si una celda visible
    // pide una imagen que ya se está calentando, se engancha a esa descarga; y si nadie
    // más la esperaba, cancelar el calentamiento cancela la descarga con él.
    //
    // Límite conocido: una celda visible que se enganche a un calentamiento que aún
    // espera hueco al fondo de la cola espera detrás de las visibles que ya estaban
    // encoladas. Como el calentamiento es secuencial, es como mucho una ronda de cuatro
    // descargas, y no compensa una promoción de prioridad para eso.
    func warm(_ urls: [URL]) async {
        for url in urls {
            guard !Task.isCancelled else { return }
            // Lo que ya está en disco no necesita ni la tarea: un stat es más barato que
            // montar la descarga para descubrir que no hacía falta
            guard !FileManager.default.fileExists(atPath: fileURL(for: url).path()) else { continue }
            _ = try? await fetch(url, priority: .prefetch)
        }
    }

    // La vista lo pone mientras el scroll va lanzado y lo quita cuando para: durante un
    // fling, cada petición que sale es cupo gastado en una celda que ya no está cuando
    // llega. Lo que hay en memoria o en disco no pasa por la cola, así que sigue
    // apareciendo; solo se retiene la salida a red.
    func setNetworkPaused(_ paused: Bool) async {
        await queue.setPaused(paused)
    }

    // MARK: - Bytes

    private struct Fetched: Sendable {
        let data: Data
        let origin: Origin
    }

    // La descarga y quiénes la están esperando.
    // Llevar la cuenta de interesados no es contabilidad de más: es lo que permite
    // cancelar. Sin ella, un scroll rápido deja cientos de peticiones vivas para
    // celdas que ya no están en pantalla, y como URLSession abre seis conexiones por
    // host, las celdas que sí se ven esperan detrás de imágenes que nadie va a mirar.
    // El síntoma es un grid lleno de huecos grises que no se rellenan nunca.
    private struct Download {
        let task: Task<Fetched, any Error>
        // Tokens y no un contador: dar de baja un token que ya no está es un no-op, y
        // así da igual que la baja llegue por el camino normal y por el de cancelación
        var waiters: Set<Int>
    }

    private func fetch(_ url: URL, priority: DownloadQueue.Priority) async throws(AppError) -> Fetched {
        let (task, token) = joinDownload(for: url, priority: priority)
        defer { leaveDownload(for: url, token: token, cancelled: false) }

        do {
            // withTaskCancellationHandler es lo que hace que cancelar la celda cancele
            // la descarga: sin él, cancelar a quien espera no cancela lo esperado, y
            // Task.value ni siquiera lanza. La petición seguiría en la cola.
            return try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                // onCancel es síncrono y está fuera del actor, así que la baja se da
                // en un salto aparte
                Task { await self.leaveDownload(for: url, token: token, cancelled: true) }
            }
        } catch let error as AppError {
            throw error
        } catch is CancellationError {
            throw .cancelled
        } catch {
            throw .unknown
        }
    }

    // La prioridad es la de quien abre la descarga. Si ya estaba en vuelo, quien llega se
    // engancha a ella tal cual: lo que no se puede duplicar es la petición.
    private func joinDownload(
        for url: URL,
        priority: DownloadQueue.Priority
    ) -> (task: Task<Fetched, any Error>, token: Int) {
        lastWaiterToken += 1
        let token = lastWaiterToken

        if var download = inFlight[url] {
            download.waiters.insert(token)
            inFlight[url] = download
            return (download.task, token)
        }

        let file = fileURL(for: url)
        let loader = self.loader
        let queue = self.queue
        let settleDelay = self.settleDelay
        let task = Task<Fetched, any Error> {
            // Disco antes que red. Leer un fichero local cuesta microsegundos y una
            // petición decenas de milisegundos, aunque acabe en un 304.
            if let stored = await Self.readFile(at: file) {
                return Fetched(data: stored, origin: .disk)
            }

            // La celda tiene que asentarse antes de que se gaste una petición por ella.
            // Si el usuario ya ha pasado de largo, para cuando termine esta espera esta
            // tarea estará cancelada y no se llega a pedir nada. Un precalentamiento no
            // es una celda que pueda irse, así que no tiene nada que asentar.
            if priority == .visible {
                try await Task.sleep(for: settleDelay)
            }
            // El hueco solo se pide para ir a la red: un acierto de disco no compite
            // por conexiones y no tiene por qué esperar a nadie
            // La firma va escrita entera porque la inferencia de throws tipado dentro
            // de un closure literal se queda en `any Error`
            let data = try await queue.enqueue(priority: priority) { () async throws(AppError) -> Data in
                try await loader(url)
            }
            // Se guardan los bytes originales y no el bitmap reducido: así, si mañana
            // la misma imagen hace falta a otro tamaño —una celda más ancha, un
            // detalle— sale del disco en vez de la red.
            await Self.writeFile(data, to: file)
            return Fetched(data: data, origin: .network)
        }

        inFlight[url] = Download(task: task, waiters: [token])
        return (task, token)
    }

    // Si el que se va era el último y se va porque le han cancelado, la descarga se
    // cancela con él: esa imagen ya no la va a ver nadie y la conexión hace falta para
    // las celdas que siguen en pantalla.
    private func leaveDownload(for url: URL, token: Int, cancelled: Bool) {
        guard var download = inFlight[url], download.waiters.remove(token) != nil else { return }

        guard download.waiters.isEmpty else {
            inFlight[url] = download
            return
        }

        inFlight[url] = nil
        if cancelled { download.task.cancel() }
    }

    // @concurrent porque el proyecto compila con SWIFT_APPROACHABLE_CONCURRENCY: sin
    // él una función nonisolated async se ejecutaría en el executor de quien llama,
    // que aquí es el propio actor, y una lectura de disco dejaría en cola a todas las
    // demás celdas. Con él sale al pool global y el actor queda libre.
    @concurrent
    private static func readFile(at url: URL) async -> Data? {
        // .mappedIfSafe: el fichero se mapea en vez de copiarse al heap, y ImageIO lee
        // de ahí directamente
        try? Data(contentsOf: url, options: .mappedIfSafe)
    }

    @concurrent
    private static func writeFile(_ data: Data, to url: URL) async {
        // Si escribir falla —disco lleno, o el sistema ha vaciado Caches/ por debajo—
        // no es motivo para no enseñar la imagen: se pierde el acierto de disco de la
        // próxima vez y nada más.
        try? data.write(to: url, options: .atomic)
    }

    @concurrent
    private static func removeFile(at url: URL) async {
        // Si no está, ya está hecho
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Decodificación

    @concurrent
    private static func downsample(_ data: Data, to pixelSize: CGSize) async -> CGImage? {
        // kCGImageSourceShouldCache: false para que ImageIO no se guarde además la
        // imagen a tamaño completo mientras fabrica la miniatura, que es justo lo que
        // se quiere evitar
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            return nil
        }

        let maxPixelSize = Int(max(pixelSize.width, pixelSize.height).rounded(.up))
        let options = [
            // Genera la miniatura aunque el fichero no traiga una incrustada, que es
            // el caso de los avatares de esta API
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            // Aplica la orientación EXIF al reducir, así lo que sale ya está derecho
            kCGImageSourceCreateThumbnailWithTransform: true,
            // Fuerza la decodificación aquí y ahora. Sin esto ImageIO la deja para
            // cuando haya que pintar, y eso pasa en el hilo principal justo durante el
            // scroll: es la diferencia entre ir fino y dar un tirón por celda.
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ] as [CFString: Any] as CFDictionary

        return CGImageSourceCreateThumbnailAtIndex(source, 0, options)
    }

    // MARK: - Claves

    // NSCache solo guarda objetos, así que la imagen viaja envuelta en una clase.
    // No hace nada más: el coste se calcula fuera, al insertar.
    private final class Entry {
        let image: CGImage
        init(_ image: CGImage) { self.image = image }
    }

    private static func pixelSize(for size: CGSize, scale: CGFloat) -> CGSize {
        CGSize(width: (size.width * scale).rounded(.up), height: (size.height * scale).rounded(.up))
    }

    private static func memoryKey(url: URL, pixelSize: CGSize) -> NSString {
        "\(url.absoluteString)|\(Int(pixelSize.width))x\(Int(pixelSize.height))" as NSString
    }

    private func fileURL(for url: URL) -> URL {
        // SHA-256 de la URL: nombre de longitud fija, sin caracteres que el sistema de
        // ficheros no admita y sin pasarse de los 255 bytes por componente, que es lo
        // que pasaría percent-encodeando una URL larga.
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return directory.appending(path: name, directoryHint: .notDirectory)
    }

    // Caches/ y no Documents/: son bytes que se pueden volver a descargar, así que ni
    // se respaldan en iCloud ni tiene sentido que el sistema los conserve cuando le
    // falte espacio.
    //
    // Falta podar el directorio: hoy crece sin límite y solo lo vacía el sistema cuando
    // necesita sitio. Se deja así a sabiendas porque los 826 avatares de la API son unos
    // 20 MB en el peor caso —cabe entero— y una poda LRU hecha con prisa borra justo lo
    // que se está usando. Entraría como un `trim(to:)` llamado al pasar la app a segundo
    // plano, ordenando los ficheros por .contentAccessDateKey y borrando los más viejos
    // hasta bajar del límite. Ver README, "Límites conocidos".
    static var defaultDirectory: URL {
        URL.cachesDirectory.appending(path: "ImageCache", directoryHint: .isDirectory)
    }

    // MARK: - Descarga

    // El reintento se añade componiendo, igual que RetryingHTTPClient hace con el
    // cliente HTTP: la descarga no sabe que se la reintenta y el reintento no sabe de
    // dónde salen los bytes.
    //
    // Este es el reintento corto: el tropiezo de una petición —un 502 pasajero, un
    // timeout— se repite aquí en cientos de milisegundos, y como la descarga está
    // deduplicada, se repite una vez para todas las celdas que estuvieran esperándola.
    // El mal rato largo, de segundos, lo cubre CachedAsyncImage mientras la celda siga
    // en pantalla; las dos capas se reparten el tiempo en vez de solaparse.
    static func retrying(
        _ loader: @escaping DataLoader,
        policy: RetryPolicy = .default
    ) -> DataLoader {
        // Las firmas van escritas enteras porque la inferencia de throws tipado dentro
        // de un closure literal se queda en `any Error`
        { (url: URL) async throws(AppError) -> Data in
            // El 429 se queda fuera a propósito, y es la diferencia entre salir del
            // agujero y cavarlo más hondo: de él se encarga el freno compartido de
            // RateLimiter. Reintentarlo aquí sería que cada una de las imágenes en
            // vuelo repitiera por su cuenta la ráfaga que nos ganó el límite.
            try await policy.attempt(
                shouldRetry: { $0.isRetryable && $0 != .rateLimited },
                { () async throws(AppError) -> Data in try await loader(url) }
            )
        }
    }

    // Descarga directa, sin pasar por HTTPClient: ahí lo que llega es JSON que hay que
    // decodificar, y aquí lo que hace falta son los bytes tal cual. Todo lo demás —la
    // ficha del limitador, la traza, el transporte y el código de estado— es el mismo
    // URLSession.perform que usa el cliente HTTP, escrito una vez para los dos.
    //
    // Solo se traza y se gasta ficha en lo que sale a la red de verdad. Lo que se
    // resuelve en memoria o en disco no llega hasta aquí, y así el log dice qué se está
    // pidiendo fuera y no cuántas celdas se han pintado. Como se llama desde dentro de la
    // cola, el orden es hueco (LIFO) primero y ficha después: la prioridad se aplica al
    // recurso escaso, que cuando el servidor aprieta es la ficha.
    static func download(_ url: URL, through limiter: RateLimiter) async throws(AppError) -> Data {
        // Petición explícita en vez de data(from:) —que monta esta misma por dentro—
        // para poder trazarla
        try await imageSession.perform(URLRequest(url: url), through: limiter).data
    }

    private static let imageSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        // Sin URLCache: los bytes ya los guardamos nosotros en Caches/, y tener dos
        // cachés de disco con lo mismo dentro es pagar el doble de espacio por nada.
        // La de URLSession se queda para las respuestas JSON, que es donde el ETag de
        // la API sí aporta.
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 15
        return URLSession(configuration: configuration)
    }()
}

private extension CGImage {
    // Lo que ocupa el bitmap ya decodificado, que es lo que de verdad pesa en memoria.
    // El tamaño del fichero comprimido no sirve como coste: son órdenes de magnitud
    // distintos y NSCache desalojaría cuando ya fuera tarde.
    var decodedByteCount: Int { bytesPerRow * height }
}
