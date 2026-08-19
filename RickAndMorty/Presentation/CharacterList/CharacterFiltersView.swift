import SwiftUI

/// The list's filters, in a separate sheet.
///
/// A sheet rather than a fixed bar above the grid, since they're touched rarely —
/// keeping them always visible costs a row's worth of height on every screen, and in a
/// grid that space is exactly what's being asked for.
///
/// Applied immediately, no "apply" button. The real list sits behind the sheet, so it's
/// already loaded on close — asking the user to also confirm a change they can already
/// see is one step too many.
struct CharacterFiltersView: View {
    // @Bindable, not per-field @Binding — the view model's accessors already know what
    // to reload and how urgently, so the view just wires them up.
    @Bindable var viewModel: CharacterListViewModel

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                // Both pickers share one section, no header: the row already says
                // "Status" and "Gender" via the Picker label, so a title above would
                // repeat it
                Section {
                    Picker(.characterFiltersStatusPickerTitle, selection: $viewModel.statusFilter) {
                        // "Any" is just another selection case, not a separate clear
                        // button — removing a filter means choosing not to filter by
                        // it, visible in the same spot it was set
                        Text(.characterFiltersStatusAny).tag(Character.Status?.none)
                        ForEach(Character.Status.allCases, id: \.self) { status in
                            Text(status.displayName).tag(Character.Status?.some(status))
                        }
                    }
                    // UI test identifier: the control's displayed text includes the
                    // chosen value ("Status, Any"), so searching by label would target
                    // something that changes on its own
                    .accessibilityIdentifier("filter-status")

                    Picker(.characterFiltersGenderPickerTitle, selection: $viewModel.genderFilter) {
                        Text(.characterFiltersGenderAny).tag(Character.Gender?.none)
                        ForEach(Character.Gender.allCases, id: \.self) { gender in
                            Text(gender.displayName).tag(Character.Gender?.some(gender))
                        }
                    }
                    .accessibilityIdentifier("filter-gender")
                }

                Section {
                    TextField(String(localized: .characterFiltersSpeciesFieldPrompt), text: $viewModel.speciesFilter)
                        // API matches species by exact text, so autocorrect and
                        // auto-capitalization only distort what the user typed on
                        // purpose
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .accessibilityIdentifier("filter-species")
                } header: {
                    Text(.characterFiltersSpeciesSectionTitle)
                } footer: {
                    Text(.characterFiltersSpeciesSectionFooter)
                }
            }
            .navigationTitle(.characterFiltersTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(.characterFiltersClearButton) { viewModel.clearFilters() }
                        .disabled(!viewModel.hasActiveFilters)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(.characterFiltersDoneButton) { dismiss() }
                }
            }
        }
        // Medium detent: filters take little space, so the list behind stays visible
        // while changing them, letting the result be checked without closing
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
