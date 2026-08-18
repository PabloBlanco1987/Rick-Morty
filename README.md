# Rick & Morty

App de iOS para navegar por el universo de Rick & Morty: rejilla paginada de
personajes, búsqueda y filtros contra el servidor, y ficha de detalle con los episodios
en los que sale cada personaje.

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/screenshots/list-dark.webp">
    <img alt="Listado de personajes" src="docs/screenshots/list-light.webp" width="150">
  </picture>&nbsp;
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/screenshots/detail-dark.webp">
    <img alt="Ficha de detalle" src="docs/screenshots/detail-light.webp" width="150">
  </picture>&nbsp;
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/screenshots/filters-dark.webp">
    <img alt="Filtros por estado, género y especie" src="docs/screenshots/filters-light.webp" width="150">
  </picture>&nbsp;
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/screenshots/search-dark.webp">
    <img alt="Búsqueda en el servidor combinada con los filtros" src="docs/screenshots/search-light.webp" width="150">
  </picture>&nbsp;
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/screenshots/empty-dark.webp">
    <img alt="Estado vacío con la acción para limpiar búsqueda y filtros" src="docs/screenshots/empty-light.webp" width="150">
  </picture>&nbsp;
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/screenshots/refresh-failed-dark.webp">
    <img alt="Aviso de refresco fallido conservando la lista" src="docs/screenshots/refresh-failed-light.webp" width="150">
  </picture>
</p>
<p align="center"><sub>Listado · Detalle · Filtros · Búsqueda · Vacío · Refresco fallido — iPhone 17, iOS 26. Las capturas siguen el tema de GitHub: en oscuro se ve la app en oscuro.</sub></p>

SwiftUI + MVVM sobre un núcleo Clean de tres capas, **sin una sola dependencia de
terceros**, con caché de imágenes propia de dos niveles y 212 pruebas automatizadas.

| | |
|---|---|
| **Mínimo** | iOS 18.0 |
| **Swift** | 6.0 (modo estricto, sin `@unchecked Sendable` en todo el proyecto) |
| **Xcode** | 26 |
| **Dependencias** | Ninguna |
| **API** | [rickandmortyapi.com](https://rickandmortyapi.com) |

---

## 1. Cómo ejecutarlo

```bash
open RickAndMorty.xcodeproj
```

Seleccionar el esquema `RickAndMorty` y ejecutar (`⌘R`). No hay nada que instalar, ni
`pod install`, ni resolución de paquetes.

Toda la suite, unitarias y de interfaz:

```bash
xcodebuild test -project RickAndMorty.xcodeproj -scheme RickAndMorty -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

SwiftLint se ejecuta en cada compilación si está instalado (`brew install swiftlint`);
si no lo está, avisa y sigue, para que el proyecto no deje de compilar en una máquina
que no lo tenga.

---

## 2. Qué hace

- **Rejilla paginada** de los 826 personajes, con scroll infinito, *prefetch* ocho
  celdas antes del final y freno entre páginas para no provocar el límite de peticiones
  del servidor.
- **Búsqueda en el servidor** con espera tras la última tecla, y **filtros** por estado,
  género y especie, combinables entre sí y con la búsqueda.
- **Ficha de detalle** con los datos del personaje y la lista de episodios, traídos en
  una única petición en lote.
- **Estados de pantalla completos**: esqueleto de carga, vacío, vacío-por-filtro, error
  con reintento, error de página con reintento, y un aviso efímero cuando un *pull to
  refresh* falla y se conserva la lista, cada uno con su texto.
- **Caché de imágenes propia**: reducción durante la decodificación, memoria y disco,
  descargas deduplicadas y cola con prioridad a lo que está en pantalla.
- **Dynamic Type y contraste**: hasta el tamaño de letra más grande sin recortes (la
  rejilla pasa a una columna, las filas de la ficha y de los episodios se apilan, los
  iconos y el punto de estado crecen con el texto), estado indicado con color *y* texto,
  textos sobre fondos tintados en color primario para que lleguen al contraste 4.5:1, y
  las dos únicas animaciones de la app respetando «reducir movimiento».
- **Un solo idioma, con catálogo**: todos los textos viven en `Localizable.xcstrings`,
  ninguno en el código, y la app se entrega en inglés.
- **Un sistema de diseño propio**: espaciados, radios, tipografía, chips y superficies
  salen de un puñado de tokens, y ninguna vista escribe un literal de estilo (§3).

---

## 3. Arquitectura

Tres capas con la dependencia apuntando siempre hacia dentro. Domain no sabe que existe
HTTP; Presentation no sabe que existe un código de estado.

```
┌──────────────────────────────────────────────────────────────┐
│ Presentation        Vistas SwiftUI + ViewModels @Observable   │
│                     ViewState<T>, textos de error             │
└───────────────────────────────┬──────────────────────────────┘
                                │ usa
┌───────────────────────────────▼──────────────────────────────┐
│ Domain              Entidades · Casos de uso · AppError       │
│                     protocol CharacterRepository  ◄───────┐   │
└───────────────────────────────────────────────────────────┼──┘
                                                            │ implementa
┌───────────────────────────────────────────────────────────┼──┐
│ Data                Repositorio · DataSource · Mappers · DTO  │
│                     HTTPClient · Endpoint · ImageCache        │
└──────────────────────────────────────────────────────────────┘
```

El protocolo `CharacterRepository` vive en **Domain**, junto a quien lo usa, y lo
implementa **Data**. Esa inversión es lo que permite que Domain compile sin conocer la
red y que cambiar la fuente de datos no toque nada por encima de un fichero.

`AppDependencies` es la única raíz de composición: el único sitio donde se nombran los
tipos concretos del grafo de datos. Lo que cruza hacia la capa de datos —el repositorio
que usa el dominio, el cliente HTTP que usa el data source— es un protocolo; los casos de
uso son structs que envuelven ese repositorio y se sustituyen por debajo, sin protocolo
propio. Es justo lo que hace que los tests de interfaz puedan arrancar la app entera con
datos en memoria sin que ninguna capa se entere.

La única pieza que no entra por ahí es la caché de imágenes, que viaja por el entorno de
SwiftUI (`@Entry var imageCache`): qué tamaño necesita una imagen es una decisión de la
vista, no del dominio, y meterla en la raíz obligaría a arrastrarla por el init de cada
pantalla intermedia para acabar en el mismo sitio.

### Flujo de una petición

```
CharacterListView → CharacterListViewModel → FetchCharactersUseCase
   → CharacterRepository (protocolo)
   → DefaultCharacterRepository → CharacterRemoteDataSource
   → RetryingHTTPClient → URLSessionHTTPClient → API
   ← Page<Character> ← CharacterMapper ← PageDTO<CharacterDTO>
```

### El sistema de diseño

`Presentation/DesignSystem/` es la respuesta a un recuento incómodo: la app tenía **seis
radios distintos** para cuatro formas, **tres opacidades de verde** que a ojo son la
misma, y un margen de pantalla que era 16 en el listado y 20 en la ficha. Ninguna de esas
cosas se ve como un fallo, pero juntas son lo que hace que una app parezca hecha a trozos.

Son tokens y media docena de componentes, y cabe en una tabla:

| Token | Valores | Dónde manda |
|---|---|---|
| `Theme.Spacing` | 2 · 4 · 8 · 12 · 16 · 24 · 32 | Todo hueco entre dos elementos |
| `Theme.Radius` | `chip` 10 · `card` 16 · `hero` 20 | Chips, superficies de contenido, la imagen de la ficha |
| `Theme.Layout` | Márgenes, anchos máximos, mínimos de columna | Lo que solo significa algo en su sitio |
| `Theme.Tint` | `accent` + un único relleno al 12% | Chips, iconos, badges |
| `Theme.Motion` | `fade`, `notice` | Las dos únicas animaciones de la app |
| `Font.*` | `cardTitle`, `label`, `chipCode`… | Alias sobre *text styles*, nunca puntos |

Encima de los tokens hay lo que se repetía a mano: `.cardSurface()` (el fondo redondeado
que estaba copiado en siete sitios con dos radios distintos), `.tintedChip(_:in:)`,
`IconTile`, `InfoRow`, `SectionHeader`, y `ErrorStateView` / `InlineErrorView` —el error a
pantalla completa estaba duplicado palabra por palabra entre el listado y la ficha—.

Cuatro reglas lo sostienen:

1. **Ninguna vista escribe un literal de estilo.** Si hace falta un número nuevo, o falta
   un token o sobra el literal.
2. **Los tokens de texto son alias sobre *text styles*, nunca tamaños en puntos.** Es la
   condición para que el Dynamic Type siga funcionando hasta AX5 sin tocar nada: un
   `.system(size: 17)` se queda clavado en 17 aunque el usuario haya pedido 43.
3. **La escala manda en las distancias entre elementos; los tamaños intrínsecos de un
   componente viven con él.** El punto del badge y el lado de la caja de un icono son
   `@ScaledMetric` propios, porque crecen con la letra y no significan nada fuera de ahí.
4. **El sistema no pelea con la plataforma.** `Form`, `ContentUnavailableView`, los
   estilos de botón y los materiales se quedan como están; se tokeniza lo que el proyecto
   ya estaba decidiendo a mano, no lo que iOS ya decide bien.

Lo que se gana no es cosmética: el contraste de los chips deja de depender de que cada
pantalla se acuerde de poner el texto en primario —lo pone el chip—, la regla de «reducir
movimiento» pasa de estar escrita en dos ficheros a estar escrita una vez, y la pantalla
siguiente se monta con piezas en lugar de con literales.

---

## 4. Decisiones que merece la pena explicar

**Errores tipados de punta a punta.** Todo el proyecto usa `throws(AppError)` en lugar
de `throws`. Quien llama puede hacer un `switch` exhaustivo sobre lo que puede fallar en
vez de recibir un `any Error` sobre el que solo cabe adivinar. `URLError`,
`DecodingError` y los códigos HTTP se traducen a `AppError` dentro de la capa de datos; de
ahí solo sale, como dato, el número de un `.server(statusCode:)`, y lo único que se decide
con él es si un 5xx merece reintento.

**El límite de peticiones (429) es un caso propio.** La API va detrás de Cloudflare y
responde 429 en cuanto se le piden varias páginas seguidas, que es exactamente lo que
produce un scroll rápido. No es un error de servidor: el servidor está bien, somos
nosotros los que vamos deprisa. Se arregla esperando, no reintentando, y por eso tiene
su propio caso y su propia espera (segundos en vez de milisegundos).

**Un solo ritmo para todo el host (`RateLimiter`).** Cloudflare limita por IP y antes de
su caché, y avatares y JSON viven en el mismo host: cada imagen y cada página cuentan
contra el mismo cupo. Por eso el ritmo al que la app sale a la red es una sola pieza que
comparten el cliente HTTP y la caché de imágenes: un cubo de fichas (ocho por segundo de
partida) y, si aun así llega un 429, un freno compartido que respeta el `Retry-After` del
servidor, baja el ritmo a la mitad y lo recupera poco a poco con los aciertos. Limitar
cuántas descargas van a la vez no bastaba: cuatro imágenes pequeñas y rápidas son
veinticinco peticiones por segundo, y era ese número —no el de celdas pintadas— el que se
ganaba el castigo y de paso tumbaba la página siguiente.

**Un enum de estado en lugar de tres banderas.** `ViewState<T>` hace imposible teclear
«cargando y con error a la vez», y convierte cada vista en un `switch` exhaustivo que el
compilador obliga a cubrir entero.

**Fallo de pantalla ≠ fallo de una parte.** Si se cae la página 7, las seis que el
usuario está mirando siguen siendo válidas: el error va al pie de la lista, no a
pantalla completa. Lo mismo en el detalle, donde un fallo de los episodios no se lleva
por delante al personaje que ya estaba en pantalla.

**Buscar es listar con un filtro puesto.** No hay un `SearchCharactersUseCase` aparte:
las reglas de paginación son idénticas y separarlos sería duplicar esa lógica para
tener otro nombre.

**`CharacterFilter.empty`, no `.none`.** `Optional` ya tiene un miembro `.none`, así que
con ese nombre una comparación como `filtros.last == .none` compila sin quejarse y
pregunta si el opcional es nulo, no si el filtro está vacío: un test en verde por el
motivo equivocado. Cambiar el nombre es lo único que hace falta para que no pueda pasar.

**Un solo idioma, pero con catálogo.** La app se entrega en inglés y solo en inglés, y es
una decisión, no algo a medias: el catálogo de strings (`Localizable.xcstrings`, con
símbolos generados por Xcode) existe para que **ningún texto visible esté en el código**,
no para traducir hoy. Cada clave lleva un comentario que dice dónde sale y para qué, y
hasta los textos que solo dan ancho a un esqueleto redactado salen de ahí. Añadir un
idioma mañana es añadir una columna al catálogo sin tocar una sola vista.

**El aviso de refresco fallido dura seis segundos.** Si un *pull to refresh* falla se
conserva la lista y aparece un aviso entre el título y la rejilla, con qué ha pasado y que
lo que se ve puede estar viejo. Se va solo, al tocarlo, o antes si otro refresco vuelve a
traer datos. El view model solo expone el fallo y la forma de descartarlo; cuánto dura y
cómo entra y sale es cosa de la vista. No hay cola porque no hay más de un emisor: un
segundo fallo mientras el aviso está en pantalla se queda con el que hay.

---

## 5. La caché de imágenes

Es la parte con más criterio del proyecto, porque una rejilla de 826 avatares es donde
un scroll se rompe. Tres gastos, en orden de impacto:

1. **Decodificar.** Un avatar de 300×300 px pesa unos 25 KB comprimido, pero su bitmap
   ocupa 360 KB, y lo que pesa en memoria es el bitmap. Aquí se decodifica **a la medida
   de la celda** y en el momento, no al ir a pintar: el bitmap nunca es mayor que lo que
   se ve, así que el techo de memoria lo pone el layout y no lo que decida mandar el
   servidor. Con los 300×300 de hoy y celdas que no bajan de 150 pt el recorte no llega a
   aplicarse —ImageIO no amplía—; lo que sí se nota en cada celda es forzar la
   decodificación ahí, fuera del hilo principal, en vez de dejarla para el momento de
   pintar, que es durante el scroll.
2. **Repetir trabajo.** Volver hacia atrás en el scroll no puede costar otra descarga:
   memoria primero, disco después, la red como último recurso. Se guardan los bytes
   originales, no el bitmap reducido, para que otro tamaño cueste una decodificación y
   no otra descarga.
3. **Pedir lo mismo dos veces a la vez.** En una rejilla es lo normal. Las descargas se
   deduplican por URL y llevan la cuenta de quién las espera; cuando el último interesado
   se va porque le han cancelado, la descarga se cancela con él.

Sobre eso, una cola propia (`DownloadQueue`) con **cuatro descargas simultáneas** y orden
**LIFO**. Lo segundo es lo importante: al bajar deprisa, la última imagen pedida es la
que el usuario tiene delante y la primera es una que dejó atrás diez pantallas antes.
En orden de llegada, el usuario ve pintarse todas las que ya no mira antes de que le
llegue la suya.

Y un detalle que ahorra la mayoría de las peticiones: una celda tiene que llevar
**120 ms en pantalla** antes de que se gaste una petición por ella. En un vistazo rápido
las celdas asoman y se van en decenas de milisegundos; pedir esas imágenes es gastar
ancho de banda en lo que nadie ha llegado a ver, y esa ráfaga es la que se gana el 429
que luego tumba la carga de la página siguiente.

Los 120 ms no aguantan un *fling*, en el que cada celda pasa por pantalla en unos 300 ms:
por eso, **mientras el scroll va lanzado** (`onScrollPhaseChange`, por encima de una
velocidad) **no sale nada a la red**. Lo que ya está en memoria o en disco sigue
apareciendo; solo se retiene la salida, y la pausa caduca sola al segundo y medio, por si
nadie la levanta.

Y para que a velocidad de lectura las celdas aparezcan ya con su imagen, **la página que
acaba de llegar se precalienta a disco** mientras el usuario todavía lee la anterior: en
secuencia, con prioridad baja en la cola —solo entra cuando no espera nada visible— y
cancelándose sola cuando llega la página siguiente. Es la sensación de que la app "ya lo
tenía" sin dejar de pintar progresivamente ni bloquear el scroll.

---

## 6. Rendimiento

La pregunta corta es «¿va fluido con los 826?», y la respuesta honesta tiene dos partes:
qué se ha hecho para que vaya, y qué se ha medido. Lo primero está en el código; lo
segundo, salvo una excepción, no, y se dice como lo que es: una expectativa razonada, no
una cifra.

### Qué se ha hecho, y qué resuelve cada cosa

| Técnica | Qué resuelve | Dónde |
|---|---|---|
| **Decodificar a la medida de la celda**, fuera del hilo principal | El bitmap no crece con lo que mande el servidor, y el tirón de decodificar no cae en el frame del scroll | `ImageCache.downsample`: ImageIO con `kCGImageSourceShouldCacheImmediately` |
| **Dos niveles de caché**: bitmaps por tamaño en memoria (`NSCache`, 50 MB) y bytes originales en disco | Volver atrás no cuesta ni descarga ni decodificación; otro tamaño cuesta una decodificación, no otra red | `ImageCache` |
| **Deduplicación por URL** con recuento de interesados | Dos celdas con la misma imagen abren una conexión, y si el último interesado se va, la descarga se cancela con él | `ImageCache.joinDownload` / `leaveDownload` |
| **Cancelación por visibilidad real** | Salir de pantalla cancela la descarga: `LazyVGrid` no destruye las celdas, así que `.task` sola no se cancelaría nunca | `CachedAsyncImage`: `.onScrollVisibilityChange` + `.task(id:)` |
| **Cola LIFO de cuatro**, visible antes que precalentamiento | Se pinta primero lo que se está mirando, no la cola de lo que quedó atrás | `DownloadQueue` |
| **Asentamiento de 120 ms** y **pausa durante el fling** | No se gasta petición ni cupo en celdas que pasan sin llegar a verse | `ImageCache.settleDelay`, `CharacterListView.onScrollPhaseChange` |
| **Prefetch de la página siguiente** ocho celdas antes del final, con 400 ms entre páginas | La página llega antes de tocar el fondo, y un gesto rápido no encadena cinco peticiones | `CharacterListViewModel` |
| **Precalentamiento a disco** de la página recién llegada, en secuencia y con prioridad baja | Las celdas de la pantalla siguiente aparecen ya con imagen sin competir con las visibles | `CharacterListView` → `ImageCache.warm` |
| **Caché de respuestas** (`URLCache` con ETag y `Cache-Control` de 90 días) | Volver del detalle o repetir una búsqueda no cuestan petición; el *pull to refresh* revalida con una condicional (304) | `URLSession.rickAndMorty`, `Freshness` |
| **Ritmo adaptativo** compartido por JSON e imágenes | Un cubo de fichas (8/s) evita ganarse el 429; si aun así llega, freno con `Retry-After`, ritmo a la mitad y recuperación gradual | `RateLimiter` |
| **Espera de 350 ms tras la última tecla** | Escribir «rick» es una petición, no cuatro | `CharacterListViewModel.searchDebounce` |
| **Celdas `Equatable`** (`.equatable()`) | Al añadir una página se construyen 20 cuerpos, no 820: las demás se descartan comparando structs | `CharacterCard` |

### Qué se ha medido y qué no

Nada de lo anterior ha pasado por Instruments. Lo único medido con el reloj es la
velocidad de deceleración que separa un *fling* de un *flick* de lectura —unos 5,5 pt/ms
frente a menos de 1, en el simulador—, porque la unidad de
`ScrollPhaseChangeContext.velocity` no está documentada y había que mirarla. Los números
que aparecen por el código y por este documento —25 KB comprimidos frente a 360 KB de
bitmap, unos 145 avatares en los 50 MB de memoria, unos 20 MB de disco para los 826— son
aritmética sobre los 300×300 px que sirve la API, no medidas.

La expectativa, razonada: el scroll no debería dar tirones, porque nada caro pasa en el
hilo principal —la decodificación va en `@concurrent` y con la caché inmediata de ImageIO,
y las celdas ya construidas no se reconstruyen—; la memoria debería quedarse por debajo
del techo de 50 MB de la caché más el coste de 826 structs, que es despreciable; y la red,
tras un recorrido completo a velocidad de lectura, debería estar en 42 páginas de JSON
más 826 imágenes, sin un solo 429. Es una expectativa: se sostiene en el diseño y en los
tests unitarios de cada pieza, no en una traza.

### Qué mediría con más tiempo

En este orden, porque cada medida confirma o desmiente algo de lo de arriba:

1. **Hitches al hacer scroll**, con la plantilla *Animation Hitches* de Instruments (y la
   de *SwiftUI* para ver qué cuerpos se reconstruyen), en dispositivo y dos veces: con
   la caché fría y con la caché caliente, bajando hasta el 826. Es la medida que dice si
   el hilo principal va limpio; si hay hitches, *Time Profiler* filtrado a ese hilo dice
   de quién son.
2. **Huella de memoria con la lista entera cargada** y todos los avatares visitados:
   *Allocations* y el gráfico de memoria, buscando dos cosas: que el pico se quede cerca
   del techo de `NSCache` —es decir, que el `cost` con el que se inserta cada bitmap
   (`bytesPerRow × height`) coincida con lo que ocupa de verdad— y que baje al recibir
   un aviso de memoria.
3. **Peticiones por recorrido completo.** La app ya trae la traza (`NetworkLogger`, solo
   en DEBUG): contar peticiones y 429 en un recorrido a velocidad de lectura y en otro a
   base de *flings*, y compararlo con la cuenta esperada. Es la métrica que valida el
   asentamiento, la pausa y el `RateLimiter`, que son las tres decisiones más opinables
   del proyecto.
4. **Tamaño de `Caches/ImageCache`** tras ese mismo recorrido, para confirmar los ~20 MB
   y decidir con datos si la poda del §8 sube de prioridad.
5. **Arranque en frío** hasta la primera rejilla pintada, con `os_signpost` en
   `AppDependencies` y en el `.task` de la lista.

---

## 7. Pruebas

**212 pruebas**: 201 unitarias en **Swift Testing** repartidas en 26 suites, y 11 de
interfaz en XCTest.

Dos reglas que sigue toda la suite:

- **Ni un solo `sleep` arbitrario.** Donde la espera es una decisión —el reintento, el
  freno entre páginas, la búsqueda— se inyecta y se registra (`SleepRecorder`), así que
  lo que se comprueba es cuánto se decide esperar y cuándo, no el reloj. Donde hace falta
  congelar una operación en vuelo se usa un rendezvous (`AsyncGate`), no un «duerme
  50 ms y confía». Es la diferencia entre una suite fiable y una que falla una vez de
  cada treinta en integración continua. Los pocos tests que sí miran el reloj de verdad
  —el cubo de fichas y el freno del `RateLimiter`, la pausa que caduca sola y la que un
  temporizador viejo no puede levantar en `DownloadQueue`, el asentamiento de una celda en
  `ImageCache` y que un precalentamiento no lo espera, y
  `doesNotBrakeWhenTheUserTakesTheirTime`— prueban precisamente que pase el tiempo, o que
  no pase, con márgenes holgados en los dos sentidos: donde se espera, dormir de más no
  puede romperlos y dormir de menos no puede pasar; donde no se espera, el tope queda un
  orden de magnitud por encima de lo que tarda la operación.
- **Las carreras se prueban congelando, no adivinando.** El repositorio de mentira puede
  retener una petición en un `AsyncGate` mientras el test cambia el criterio, refresca o
  pide otra página, y soltarla después: así se comprueba qué se hace con una respuesta
  que llega tarde —una búsqueda vieja, una página pedida durante un refresco, un refresco
  que vuelve con otro filtro puesto— sin depender de que el planificador ordene las
  cosas como el test espera.
- **Los tests de interfaz no tocan la red.** Se lanzan con el argumento
  `-stubbed-data` y la app monta el mismo grafo sobre un repositorio en memoria. Un test
  de interfaz contra la API de verdad se pone rojo el día que no hay cobertura y el día
  que la API responde 429, y ninguna de las dos cosas es un fallo de la app. Con
  `-stubbed-refresh-fails` ese mismo repositorio falla al refrescar, que es lo que deja
  ver el aviso sin depender de que no haya red; y el recorrido de Dynamic Type arranca
  la app con el tamaño de letra más grande que existe
  (`-UIPreferredContentSizeCategoryName`) y comprueba que todo sigue en pantalla y se
  puede tocar.

Lo que se cubre, por capas:

| Capa | Qué se prueba |
|---|---|
| Domain | Paginación, filtros y su normalización, qué error merece reintento y con cuánta paciencia, coordinación del detalle, y que la frescura llega al repositorio |
| Data | Construcción y escapado de URLs, frescura → política de caché en cada capa, la tabla completa de traducción de errores (`URLError` y códigos HTTP), decodificación, mapeo con degradación (estado, género, lugar «unknown», URL de imagen no absoluta, fecha en GMT), reintentos, esperas y cancelación, limitador de ritmo (fichas, freno, `Retry-After`, ritmo adaptativo, y qué 429 y qué aciertos cuentan), cola con prioridad, pausa y hueco devuelto al fallar, caché de imágenes (tamaño, memoria, disco, deduplicación, cancelación de uno de dos interesados, bytes envenenados, qué se reintenta) y precalentamiento |
| Presentation | Carga, paginación y deduplicación de personajes, freno entre páginas, refresco y su aviso cuando falla, búsqueda con espera, filtros, la acción de la pantalla vacía, qué se conserva cuando algo falla o se cancela, y las carreras: respuestas que llegan tarde tras cambiar el criterio o refrescar. Además, que cada icono de error es un símbolo que existe, que los textos no se repiten, y que la fecha de emisión se lee el día que fue aunque el dispositivo esté al oeste de Greenwich |
| App | El repositorio en memoria con el que arrancan los tests de interfaz pagina y filtra como el servidor |
| Interfaz | Que las piezas están conectadas: lista → detalle con sus episodios → volver conservando la página a la que se había bajado, scroll infinito hasta la segunda página, búsqueda, vacío y su botón, filtros y su «Clear»; las tres pantallas con el tamaño de letra máximo; y el aviso de refresco fallido, que aparece, conserva la lista y se descarta |

---

## 8. Límites conocidos

Cosas que faltan **a sabiendas**, no por descuido. Cada una está comentada en el código,
en el punto exacto donde entraría, como un `TODO: [Fuera de alcance · README §8]` con
tres partes —qué falta, por qué se decidió no hacerlo y por dónde entraría—, de modo que
`grep -rn "TODO:" RickAndMorty` las lista a las tres y no encuentra ninguna más:

- **Poda de la caché de disco**
  ([`ImageCache.swift`](RickAndMorty/Data/Cache/ImageCache.swift)). Hoy el directorio
  crece sin límite y solo lo vacía el sistema cuando necesita espacio. Los 826 avatares
  son unos 20 MB en el peor caso, así que cabe entero; entraría como un `trim(to:)` al
  pasar a segundo plano, ordenando por fecha de último acceso.
- **Reintento de imágenes desde la lista**
  ([`CachedAsyncImage.swift`](RickAndMorty/Presentation/Common/CachedAsyncImage.swift)).
  Una imagen que agota sus reintentos deja el hueco hasta que la celda sale y vuelve a
  entrar en pantalla. Entraría como una señal de reintento en el entorno que formara
  parte de la identidad de la tarea de carga.
- **Detalle por enlace profundo con episodios caídos**
  ([`FetchCharacterDetailUseCase.swift`](RickAndMorty/Domain/UseCases/FetchCharacterDetailUseCase.swift)).
  Llegando desde la lista, un fallo de episodios conserva el personaje. Entrando
  directamente al detalle no hay nada que conservar y se pierde también el personaje, que
  sí había llegado; hacerlo bien pide un tipo de resultado parcial.

---

## 9. Siguientes pasos

El §8 dice qué falta a sabiendas; esto dice hacia dónde seguiría, y por qué en este
orden. El criterio: primero lo que convierte expectativas en datos, después lo que el
diseño ya tiene preparado, y al final lo que abre superficie nueva.

1. **Medir antes de tocar** (las cinco medidas del §6). El proyecto tiene decisiones —los
   120 ms de asentamiento, la velocidad de *fling*, las ocho fichas por segundo— que se
   calibraron con criterio pero sin traza. Con los datos delante, cambiaría antes un
   número que una pieza; sin ellos, todo lo demás se prioriza a ojo.
2. **Cerrar los tres límites del §8**, en el orden en que están: la poda de disco es la
   más barata y la que un teléfono con poco espacio agradece; el reintento desde la lista
   es la que el usuario ve; y el resultado parcial del detalle solo importa cuando exista
   una entrada al detalle que no sea la lista, que es el punto siguiente.
3. **Enlace profundo al detalle** (`rickandmorty://character/1`, y de ahí *universal
   links*). El detalle ya se pide por id y no da por hecho que venga de la lista: está
   diseñado para esto. Es un `onOpenURL` en `RootView` que empuje el destino a la pila,
   y es lo que le da sentido al tercer límite.
4. **iPad y pantalla partida**, con `NavigationSplitView`: la rejilla a la izquierda y el
   detalle a la derecha. La navegación ya va por valor y el detalle ya no cuenta con
   destruirse al volver —`onAppear` solo carga la primera vez—, así que el trabajo es de
   layout, no de estado.
5. **Contar el «sin conexión»**. `URLCache` ya sirve una página vista sin tocar la red y
   las imágenes ya están en disco, así que arrancar sin red con lo que se vio ayer sale
   casi gratis; lo que falta es que la app lo diga —un aviso como el de refresco fallido,
   con «mostrando lo guardado»— en vez de dejar que se descubra por un error de red.
6. **Un segundo idioma**, para cobrar el catálogo que hoy es una columna sola por diseño
   (§4). Traducir es lo de menos; lo que se comprueba es que ninguna vista se rompe con
   textos un 30 % más largos, y el recorrido de Dynamic Type ya hace ese trabajo en el
   otro eje.
7. **Integración continua**: compilar, pasar la suite y SwiftLint en cada *push*. El
   `xcodebuild test` del §1 es el flujo entero; lo que falta es el fichero que lo
   ejecute lejos de esta máquina.

---

## 10. Convenciones

- **Código, identificadores y textos de la interfaz en inglés.** Los textos, además,
  nunca en el código: en `Localizable.xcstrings`, con su comentario. Los comentarios y
  esta documentación, en español: son la explicación del *porqué* de cada decisión, y
  esa es la conversación que se tiene con quien lee el código.
- **Los comentarios explican decisiones, no sintaxis.** Si un comentario se limita a
  repetir lo que hace la línea de abajo, sobra. Los que hay están donde alguien —incluido
  yo dentro de seis meses— se preguntaría «¿y esto por qué está así?».
- **Un `TODO` es un límite asumido, no deuda.** Lleva el marcador
  `[Fuera de alcance · README §8]`, sus tres partes y su entrada en el §8; si algo no cabe
  en esas tres partes, no es un TODO. Por eso SwiftLint no lo cuenta como aviso (`todo:
  only: [FIXME]`) y sí cuenta un `FIXME`, que es la marca de lo que está roto y hay que
  resolver.
- **Ningún literal de estilo en una vista.** Espaciados, radios, fuentes, tintes y
  animaciones salen de `Theme` y de los tokens de `Font`; si hace falta un valor que no
  existe, se añade al sistema y no a la vista. Es lo que mantiene las pantallas parecidas
  entre sí sin que nadie tenga que acordarse de nada.
- **SwiftLint con reglas *opt-in* elegidas una a una**, para que el linter señale
  problemas de verdad y no preferencias personales. El proyecto compila con cero avisos.
