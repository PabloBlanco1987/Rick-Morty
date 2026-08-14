import Foundation

// De dónde salen los personajes, visto desde el dominio.
// El protocolo vive aquí, al lado de quien lo usa, y lo implementa la capa de datos.
// Esa es la inversión de dependencias en la que se apoya todo: Domain compila sin
// enterarse de que existe HTTP, y cambiar la fuente (caché, fixtures, base local)
// no toca nada por encima de este fichero.
// El throws(AppError) tipado es a propósito: quien llame puede hacer un switch
// exhaustivo sobre los errores en vez de comerse un any Error.
protocol CharacterRepository: Sendable {
    func characters(page: Int, filter: CharacterFilter) async throws(AppError) -> Page<Character>
    func character(id: Int) async throws(AppError) -> Character
    func episodes(ids: [Int]) async throws(AppError) -> [Episode]
}
