import HearthstockCore
import SwiftUI

/// Add or edit a location: name, parent, climate (or inherit), humidity, and the kit switches (Decision 10).
struct LocationForm: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var location: Location
    @State private var isKit: Bool
    @State private var countsTowardRunway: Bool
    @State private var writeError: String?
    @State private var deleteProblem: String?
    @State private var confirmingDelete = false
    private let kit: Kit?
    private let inputs: RunwayInputs
    private let isNew: Bool

    init(location: Location, kit: Kit?, inputs: RunwayInputs, isNew: Bool) {
        _location = State(initialValue: location)
        _isKit = State(initialValue: kit != nil || location.kitID != nil)
        _countsTowardRunway = State(initialValue: kit?.countsTowardSiteRunway ?? false)
        self.kit = kit
        self.inputs = inputs
        self.isNew = isNew
    }

    private var parents: [[Location]] { LocationTree.possibleParents(for: location, in: inputs.locations) }

    private var parent: Location? { location.parentID.flatMap { id in inputs.locations.first { $0.id == id } } }

    /// What "inherit" means right now: the parent's resolved class, or the fallback at the top level.
    private var inheritedClimate: ClimateClass {
        guard let parentID = location.parentID else { return .fallback }
        let lookup = Dictionary(inputs.locations.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return (try? resolvedClimate(of: parentID, locations: lookup)) ?? .fallback
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Name") {
                    TextField("Garage shelf", text: $location.name).multilineTextAlignment(.trailing)
                }
                Picker("Inside", selection: $location.parentID) {
                    Text("Nothing (top level)").tag(LocationID?.none)
                    ForEach(parents, id: \.last!.id) { path in
                        Text(path.map(\.name).joined(separator: " › ")).tag(Optional(path.last!.id))
                    }
                }
            }

            Section {
                climateRow(nil)
                ForEach(ClimateClass.allCases, id: \.self) { climateRow($0) }
            } header: {
                Text("Storage climate")
            } footer: {
                Text("The multiplier stretches or shrinks how long food stays good past its printed date. Heat roughly halves shelf life for every 18 °F.")
            }

            Section {
                Picker("Humidity", selection: $location.humidity) {
                    Text(location.parentID == nil ? "Not set" : "Inherit").tag(Humidity?.none)
                    ForEach(Humidity.allCases, id: \.self) { Text($0.title).tag(Optional($0)) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.hsCard)
            } header: {
                Text("Humidity")
            } footer: {
                Text("Humid spots flag cans, cardboard and paper for rust or mold. Sealed buckets and Mylar are fine.")
            }

            Section {
                Toggle("This is a kit", isOn: $isKit.animation())
                if isKit {
                    Toggle("Counts toward runway", isOn: $countsTowardRunway)
                }
            } header: {
                Text("Kit")
            } footer: {
                Text("Kits like go-bags are packed to leave with you, so their contents stay out of your home runway unless you turn it on.")
            }

            if !isNew {
                Section {
                    Button("Delete location", role: .destructive) { confirmingDelete = true }
                        .frame(maxWidth: .infinity)
                } footer: {
                    if let deleteProblem {
                        Text(deleteProblem).foregroundStyle(Color.hsRed)
                    }
                }
            }
        }
        .hearthList()
        .navigationTitle(isNew ? "New location" : location.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isNew {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(location.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .confirmationDialog("Delete \(location.name)?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { delete() }
        }
        .errorAlert($writeError)
    }

    private func climateRow(_ climate: ClimateClass?) -> some View {
        Button {
            location.climateClass = climate
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "checkmark")
                    .foregroundStyle(Color.hsTint)
                    .opacity(location.climateClass == climate ? 1 : 0)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    if let climate {
                        Text(climate.title).font(.headline)
                        Text(climate.examples).font(.footnote).foregroundStyle(Color.hsInk2)
                    } else {
                        Text(parent.map { "Inherit from \($0.name)" } ?? "Not set").font(.headline)
                        Text(parent == nil ? "Treated as \(inheritedClimate.title.lowercased())" : "Currently \(inheritedClimate.title)")
                            .font(.footnote).foregroundStyle(Color.hsInk2)
                    }
                }
                Spacer()
                Text((climate ?? inheritedClimate).multiplierText)
                    .font(.footnote.weight(.semibold)).numeric().foregroundStyle(Color.hsInk2)
            }
            .foregroundStyle(Color.hsInk)
            .contentShape(Rectangle())
        }
        .accessibilityAddTraits(location.climateClass == climate ? .isSelected : [])
    }

    private func save() {
        var saved = location
        saved.name = saved.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let services = session.services
        let (kit, isKit, counts) = (kit, isKit, countsTowardRunway)
        Task {
            do {
                try await services.locations.save(saved)
                if isKit {
                    var updated = kit ?? Kit(locationID: saved.id)
                    updated.countsTowardSiteRunway = counts
                    try await services.kits.save(updated)
                } else if let kit {
                    try await services.kits.delete(kit.id)
                }
                dismiss()
            } catch {
                writeError = ErrorText.describe(error)
            }
        }
    }

    private func delete() {
        Task {
            do {
                try await session.services.locations.delete(location.id)
                dismiss()
            } catch let error as RepositoryError {
                deleteProblem = deleteExplanation(error)
            } catch {
                writeError = ErrorText.describe(error)
            }
        }
    }

    /// Why the location can't go, with counts where the snapshot has them.
    private func deleteExplanation(_ error: RepositoryError) -> String {
        switch error {
        case .locationHasLots:
            let count = inputs.lots.filter { $0.locationID == location.id }.count
            let held = count > 0 ? "\(count) \(count == 1 ? "item" : "items")" : "used-up items kept for history"
            return "Can't delete: \(location.name) still holds \(held). Move or delete them first."
        case .locationHasChildren:
            let names = inputs.locations.filter { $0.parentID == location.id }.map(\.name)
            return "Can't delete: \(names.joined(separator: ", ")) \(names.count == 1 ? "is" : "are") inside it. Move or delete \(names.count == 1 ? "it" : "them") first."
        case .locationHasKit:
            return "Can't delete: this location is a kit. Turn off \"This is a kit\" and save first."
        default:
            return ErrorText.describe(error)
        }
    }
}
