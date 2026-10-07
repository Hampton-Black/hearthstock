import HearthstockCore
import SwiftUI

/// Add or edit one person: name and daily needs. Saves through the person repository; the Settings list updates
/// from its subscription.
struct PersonForm: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var person: Person
    @State private var writeError: String?
    @State private var confirmingDelete = false
    private let isNew: Bool

    init(person: Person, isNew: Bool) {
        _person = State(initialValue: person)
        self.isNew = isNew
    }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $person.name)
                    .textContentType(.name)
            }
            Section {
                LabeledContent("Calories a day") {
                    TextField("kcal", value: $person.kcalPerDay, format: .number.precision(.fractionLength(0)))
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .numeric()
                }
                LabeledContent("Water a day") {
                    HStack(spacing: 4) {
                        TextField("gal", value: $person.waterGalPerDay, format: .number.precision(.fractionLength(0...2)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .numeric()
                        Text("gal").foregroundStyle(Color.hsInk2)
                    }
                }
            } footer: {
                Text("New people start at 2,000 kcal and 1 gal of water a day; adjust for age, size and work.")
            }
            if !isNew {
                Section {
                    Button("Remove from household", role: .destructive) { confirmingDelete = true }
                }
            }
        }
        .hearthList()
        .navigationTitle(isNew ? "New person" : person.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isNew {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }.disabled(!isValid)
            }
        }
        .confirmationDialog("Remove \(person.name)?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Remove", role: .destructive) { delete() }
        } message: {
            Text("Runway will be computed without them.")
        }
        .errorAlert($writeError)
    }

    private var isValid: Bool {
        !person.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && person.kcalPerDay.isFinite && person.kcalPerDay >= 0
            && person.waterGalPerDay.isFinite && person.waterGalPerDay >= 0
    }

    private func save() {
        var saved = person
        saved.name = saved.name.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            do {
                try await session.services.people.save(saved)
                dismiss()
            } catch {
                writeError = ErrorText.describe(error)
            }
        }
    }

    private func delete() {
        Task {
            do {
                try await session.services.people.delete(person.id)
                dismiss()
            } catch {
                writeError = ErrorText.describe(error)
            }
        }
    }
}
