import SwiftUI

// Los filtros del listado, en una hoja aparte.
//
// Van en una hoja y no en una barra fija encima del grid porque se tocan una vez cada
// muchas: dejarlos siempre a la vista cuesta el alto de una fila de personajes en cada
// pantalla, y en un grid ese sitio es justo lo que se está pidiendo.
//
// Se aplican al momento, sin botón de "aplicar". Detrás de la hoja está la lista de
// verdad, así que al cerrar ya está cargada: pedirle además al usuario que confirme un
// cambio cuyo resultado puede ver es un paso de más.
struct CharacterFiltersView: View {
    // @Bindable y no @Binding de cada campo: los accesos del view model ya son los que
    // saben qué hay que recargar y con cuánta prisa, así que la vista solo los enchufa.
    @Bindable var viewModel: CharacterListViewModel

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "characterFilters.statusSection.title")) {
                    Picker(String(localized: "characterFilters.statusPicker.title"), selection: $viewModel.statusFilter) {
                        // "Any" es un caso más de la selección y no un botón de quitar
                        // aparte: quitar un filtro es elegir no filtrar por él, y así se
                        // ve en el mismo sitio en el que se puso
                        Text(String(localized: "characterFilters.status.any")).tag(Character.Status?.none)
                        ForEach(Character.Status.allCases, id: \.self) { status in
                            Text(status.displayName).tag(Character.Status?.some(status))
                        }
                    }
                    // Identificador para los tests de UI: el texto que enseña el control
                    // lleva dentro el valor elegido ("Status, Any"), así que buscarlo por
                    // etiqueta sería buscar algo que cambia solo
                    .accessibilityIdentifier("filter-status")
                }

                Section(String(localized: "characterFilters.genderSection.title")) {
                    Picker(String(localized: "characterFilters.genderPicker.title"), selection: $viewModel.genderFilter) {
                        Text(String(localized: "characterFilters.gender.any")).tag(Character.Gender?.none)
                        ForEach(Character.Gender.allCases, id: \.self) { gender in
                            Text(gender.displayName).tag(Character.Gender?.some(gender))
                        }
                    }
                    .accessibilityIdentifier("filter-gender")
                }

                Section {
                    TextField(String(localized: "characterFilters.species"), text: $viewModel.speciesFilter)
                        // La API compara la especie por texto, así que ni el corrector ni
                        // la mayúscula automática ayudan aquí: solo cambian lo que el
                        // usuario ha escrito a propósito
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .accessibilityIdentifier("filter-species")
                } header: {
                    Text("Species")
                } footer: {
                    Text("The server matches partial names, so \"hum\" already finds humans.")
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Clear") { viewModel.clearFilters() }
                        .disabled(!viewModel.hasActiveFilters)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        // Media hoja: los filtros ocupan poco y así la lista de detrás sigue viéndose
        // mientras se cambian, que es lo que deja comprobar el resultado sin cerrar
        .presentationDetents([.medium, .large])
    }
}

#Preview {
    CharacterFiltersView(
        viewModel: CharacterListViewModel(
            fetchCharacters: AppDependencies.live().fetchCharacters
        )
    )
}
