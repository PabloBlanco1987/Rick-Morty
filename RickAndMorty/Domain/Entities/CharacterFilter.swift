import Foundation

// Criterios por los que se puede acotar el listado.
// Para el dominio buscar y filtrar son lo mismo: los dos recortan la misma lista,
// así que comparten tipo y caso de uso en vez de duplicar la paginación.
struct CharacterFilter: Hashable, Sendable {
    var name: String = ""
    var status: Character.Status?
    var gender: Character.Gender?
    var species: String = ""

    static let none = CharacterFilter()

    // Escribir solo espacios no cuenta como búsqueda
    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedSpecies: String {
        species.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isEmpty: Bool {
        trimmedName.isEmpty && status == nil && gender == nil && trimmedSpecies.isEmpty
    }
}
