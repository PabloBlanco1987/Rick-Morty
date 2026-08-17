import Foundation

// De dónde salen los personajes, visto desde el dominio.
// El protocolo vive aquí, al lado de quien lo usa, y lo implementa la capa de datos.
// Esa es la inversión de dependencias en la que se apoya todo: Domain compila sin
// enterarse de que existe HTTP, y cambiar la fuente (caché, fixtures, base local)
// no toca nada por encima de este fichero.
// El throws(AppError) tipado es a propósito: quien llame puede hacer un switch
// exhaustivo sobre los errores en vez de comerse un any Error.
protocol CharacterRepository: Sendable {
    func characters(page: Int, filter: CharacterFilter, freshness: Freshness) async throws(AppError) -> Page<Character>
    func character(id: Int) async throws(AppError) -> Character
    func episodes(ids: [Int]) async throws(AppError) -> [Episode]
}

// Cuánta frescura exige quien pide una página.
//
// Existe por el pull to refresh. El dominio no sabe qué es una caché HTTP, pero sí sabe
// que ese gesto significa "tráemelo otra vez" y no "dame lo que tengas": sin decirlo,
// la capa de datos no tiene forma de distinguir una página que se pide por primera vez
// de una que el usuario acaba de pedir a propósito, y le sirve la segunda de lo que
// guardó la primera vez —que es exactamente no refrescar nada.
enum Freshness: Sendable {
    // Vale lo que haya guardado mientras siga vigente. Es lo normal: una página ya
    // vista, una búsqueda repetida, volver del detalle
    case acceptCached
    // Hay que preguntarle a la fuente si ha cambiado aunque lo guardado siga vigente
    case fresh
}
