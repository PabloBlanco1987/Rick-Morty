import Foundation

// El catálogo de endpoints que usa la app.
// Teniendo todas las rutas y nombres de parámetros en un fichero, el vocabulario de
// la API aparece una sola vez. CharacterFilter es un tipo de dominio; traducirlo a
// ?status=alive&gender=female es cosa de la capa de datos y va aquí.
enum RickAndMortyAPI {
    // La base por partes, en vez de parseada desde un string.
    // URLComponents no puede fallar al construirse, así que aquí no hay que dar por
    // bueno ningún literal. El único punto donde montar la URL todavía puede fallar
    // es Endpoint.urlRequest, y ahí ya se avisa.
    static let base: URLComponents = {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "rickandmortyapi.com"
        components.path = "/api"
        return components
    }()

    static func characters(page: Int, filter: CharacterFilter = .none) -> Endpoint {
        var items = [URLQueryItem(name: "page", value: String(page))]

        if !filter.trimmedName.isEmpty {
            items.append(URLQueryItem(name: "name", value: filter.trimmedName))
        }
        if let status = filter.status {
            items.append(URLQueryItem(name: "status", value: status.rawValue))
        }
        if let gender = filter.gender {
            items.append(URLQueryItem(name: "gender", value: gender.rawValue))
        }
        if !filter.trimmedSpecies.isEmpty {
            items.append(URLQueryItem(name: "species", value: filter.trimmedSpecies))
        }

        return Endpoint(path: "/character", queryItems: items)
    }

    static func character(id: Int) -> Endpoint {
        Endpoint(path: "/character/\(id)")
    }

    // Endpoint de lote: una petición para todos los episodios de un personaje en
    // vez de una por episodio.
    // Ojo al cambio de forma que esconde: /episode/1,2 contesta con un array y
    // /episode/1 con un objeto suelto. Eso lo absorbe CharacterRemoteDataSource.
    static func episodes(ids: [Int]) -> Endpoint {
        Endpoint(path: "/episode/\(ids.map(String.init).joined(separator: ","))")
    }
}
