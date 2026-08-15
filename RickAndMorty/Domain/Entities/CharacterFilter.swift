import Foundation

// Criterios por los que se puede acotar el listado.
// Para el dominio buscar y filtrar son lo mismo: los dos recortan la misma lista,
// así que comparten tipo y caso de uso en vez de duplicar la paginación.
struct CharacterFilter: Hashable, Sendable {
    var name: String = ""
    var status: Character.Status?
    var gender: Character.Gender?
    var species: String = ""

    // Se llama `empty` y no `none` por una razón muy concreta: `Optional` ya tiene un
    // miembro `.none`, así que con ese nombre una comparación como
    // `requestedFilters.last == .none` compila sin quejarse y pregunta si el opcional
    // es nil, no si el filtro está vacío. Es un fallo silencioso —el test pasa a verde
    // por el motivo equivocado— y el nombre es lo único que hay que cambiar para que no
    // pueda ocurrir. Además queda al lado de `Page.empty`, que ya usa esa palabra.
    static let empty = CharacterFilter()

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

    // El mismo filtro con los textos ya recortados.
    //
    // Existe porque hay dos sitios que deciden sobre lo mismo y tienen que decidir
    // igual: quién dispara una recarga y quién descarta una respuesta que ya no vale.
    // El primero compara sobre el recortado —añadir un espacio no es buscar otra cosa—,
    // así que si el segundo comparase los campos crudos vería un criterio distinto donde
    // no lo hay, tiraría una respuesta buena y dejaría la pantalla cargando para siempre.
    var normalized: CharacterFilter {
        var copy = self
        copy.name = trimmedName
        copy.species = trimmedSpecies
        return copy
    }
}
