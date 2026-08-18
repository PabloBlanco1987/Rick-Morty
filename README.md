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

## 6. Pruebas

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

## 7. Límites conocidos

Cosas que faltan **a sabiendas**, no por descuido. Están comentadas en el código, en el
punto exacto donde entrarían:

- **Poda de la caché de disco.** Hoy el directorio crece sin límite y solo lo vacía el
  sistema cuando necesita espacio. Los 826 avatares son unos 20 MB en el peor caso, así
  que cabe entero; entraría como un `trim(to:)` al pasar a segundo plano, ordenando por
  fecha de último acceso.
- **Reintento de imágenes desde la lista.** Una imagen que agota sus reintentos deja el
  hueco hasta que la celda sale y vuelve a entrar en pantalla. Entraría como una señal de
  reintento en el entorno que formara parte de la identidad de la tarea de carga.
- **Detalle por enlace profundo con episodios caídos.** Llegando desde la lista, un fallo
  de episodios conserva el personaje. Entrando directamente al detalle no hay nada que
  conservar y se pierde también el personaje, que sí había llegado; hacerlo bien pide un
  tipo de resultado parcial.

---

## 8. Convenciones

- **Código, identificadores y textos de la interfaz en inglés.** Los textos, además,
  nunca en el código: en `Localizable.xcstrings`, con su comentario. Los comentarios y
  esta documentación, en español: son la explicación del *porqué* de cada decisión, y
  esa es la conversación que se tiene con quien lee el código.
- **Los comentarios explican decisiones, no sintaxis.** Si un comentario se limita a
  repetir lo que hace la línea de abajo, sobra. Los que hay están donde alguien —incluido
  yo dentro de seis meses— se preguntaría «¿y esto por qué está así?».
- **SwiftLint con reglas *opt-in* elegidas una a una**, para que el linter señale
  problemas de verdad y no preferencias personales. El proyecto compila con cero avisos.
