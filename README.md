# Rick & Morty

App de iOS para navegar por el universo de Rick & Morty: rejilla paginada de
personajes, búsqueda y filtros contra el servidor, y ficha de detalle con los episodios
en los que sale cada personaje.

SwiftUI + MVVM sobre un núcleo Clean de tres capas, **sin una sola dependencia de
terceros**, con caché de imágenes propia de dos niveles y 117 pruebas automatizadas.

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
  con reintento y error de página con reintento, cada uno con su texto.
- **Caché de imágenes propia**: reducción durante la decodificación, memoria y disco,
  descargas deduplicadas y cola con prioridad a lo que está en pantalla.
- **Accesibilidad**: VoiceOver con una parada por celda, Dynamic Type hasta tamaños de
  accesibilidad (la rejilla pasa a una columna), estado indicado con color *y* texto,
  y respeto por «reducir movimiento».

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

`AppDependencies` es la única raíz de composición: el único sitio de toda la app donde
se nombra un tipo concreto. De ahí para abajo todo son protocolos, que es justo lo que
hace que los tests de interfaz puedan arrancar la app entera con datos en memoria sin
que ninguna capa se entere.

### Flujo de una petición

```
CharacterListView → CharacterListViewModel → FetchCharactersUseCase
   → CharacterRepository (protocolo)
   → DefaultCharacterRepository → CharacterRemoteDataSource
   → RetryingHTTPClient → URLSessionHTTPClient → API
   ← PageDTO<CharacterDTO> ← CharacterMapper ← Page<Character>
```

---

## 4. Decisiones que merece la pena explicar

**Errores tipados de punta a punta.** Todo el proyecto usa `throws(AppError)` en lugar
de `throws`. Quien llama puede hacer un `switch` exhaustivo sobre lo que puede fallar en
vez de recibir un `any Error` sobre el que solo cabe adivinar. `URLError`,
`DecodingError` y los códigos HTTP se traducen a `AppError` dentro de la capa de datos y
no salen nunca de ahí.

**El límite de peticiones (429) es un caso propio.** La API va detrás de Cloudflare y
responde 429 en cuanto se le piden varias páginas seguidas, que es exactamente lo que
produce un scroll rápido. No es un error de servidor: el servidor está bien, somos
nosotros los que vamos deprisa. Se arregla esperando, no reintentando, y por eso tiene
su propio caso, su propia espera (segundos en vez de milisegundos) y un freno
*compartido* en la cola de descargas.

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

---

## 5. La caché de imágenes

Es la parte con más criterio del proyecto, porque una rejilla de 826 avatares es donde
un scroll se rompe. Tres gastos, en orden de impacto:

1. **Decodificar.** Un avatar de 300×300 px pesa unos 25 KB comprimido, pero su bitmap
   ocupa 360 KB. Para pintarlo en una celda de 110 pt eso es guardar cuatro veces los
   píxeles que se ven. Aquí se reduce **durante** la decodificación, así que el bitmap
   grande no llega a existir.
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

---

## 6. Pruebas

**117 pruebas**: 110 unitarias en **Swift Testing** repartidas en 17 suites, y 7 de
interfaz en XCTest.

Dos reglas que sigue toda la suite:

- **Ni un solo `sleep` arbitrario.** Las esperas se inyectan y se registran
  (`SleepRecorder`), así que lo que se comprueba es la *decisión* de esperar y cuánto,
  no el reloj. Donde hace falta congelar una operación en vuelo se usa un rendezvous
  (`AsyncGate`), no un «duerme 50 ms y confía». Es la diferencia entre una suite fiable y
  una que falla una vez de cada treinta en integración continua.
- **Los tests de interfaz no tocan la red.** Se lanzan con el argumento
  `-stubbed-data` y la app monta el mismo grafo sobre un repositorio en memoria. Un test
  de interfaz contra la API de verdad se pone rojo el día que no hay cobertura y el día
  que la API responde 429, y ninguna de las dos cosas es un fallo de la app.

Lo que se cubre, por capas:

| Capa | Qué se prueba |
|---|---|
| Domain | Paginación, filtros, qué error merece reintento y con cuánta paciencia, coordinación del detalle |
| Data | Construcción y escapado de URLs, traducción de errores, decodificación, mapeo con degradación, reintentos y esperas, caché de imágenes y cola |
| Presentation | Carga, paginación, deduplicación de peticiones, freno entre páginas, refresco, búsqueda con espera, filtros, y qué se conserva cuando algo falla |
| Interfaz | Que las piezas están conectadas: lista → detalle → volver, búsqueda, vacío y filtros |

---

## 7. Límites conocidos

Cosas que faltan **a sabiendas**, no por descuido. Están comentadas en el código, en el
punto exacto donde entrarían:

- **Localización.** Los textos están en inglés y escritos en el código. El sitio ya está
  preparado: entrarían como `LocalizedStringResource` sobre un String Catalog sin cambiar
  la forma de `AppError+Presentation` ni tocar una sola vista.
- **Poda de la caché de disco.** Hoy el directorio crece sin límite y solo lo vacía el
  sistema cuando necesita espacio. Los 826 avatares son unos 20 MB en el peor caso, así
  que cabe entero; entraría como un `trim(to:)` al pasar a segundo plano, ordenando por
  fecha de último acceso.
- **Aviso de refresco fallido.** Si un *pull to refresh* falla, se conserva la lista
  —que es lo importante— pero el usuario no se entera de que puede estar viendo algo
  viejo. El sitio natural es un aviso efímero, y montarlo bien (cola, duración, que
  VoiceOver lo anuncie) es una pieza en sí misma.
- **Reintento de imágenes desde la lista.** Una imagen que agota sus reintentos deja el
  hueco hasta que la celda sale y vuelve a entrar en pantalla. Entraría como una señal de
  reintento en el entorno que formara parte de la identidad de la tarea de carga.
- **Detalle por enlace profundo con episodios caídos.** Llegando desde la lista, un fallo
  de episodios conserva el personaje. Entrando directamente al detalle no hay nada que
  conservar y se pierde también el personaje, que sí había llegado; hacerlo bien pide un
  tipo de resultado parcial.

---

## 8. Convenciones

- **Código, identificadores y textos de la interfaz en inglés.** Los comentarios y esta
  documentación, en español: son la explicación del *porqué* de cada decisión, y esa es
  la conversación que se tiene con quien lee el código.
- **Los comentarios explican decisiones, no sintaxis.** Si un comentario se limita a
  repetir lo que hace la línea de abajo, sobra. Los que hay están donde alguien —incluido
  yo dentro de seis meses— se preguntaría «¿y esto por qué está así?».
- **SwiftLint con reglas *opt-in* elegidas una a una**, para que el linter señale
  problemas de verdad y no preferencias personales. El proyecto compila con cero avisos.
