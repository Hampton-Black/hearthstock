import HearthstockCore
import SwiftUI

/// Edit a lot's dates, place and notes. Quantity changes go through Use or Adjust; the product through Edit product.
struct LotEditForm: View {
    @Environment(AppSession.self) private var session
    @Environment(Today.self) private var today
    @Environment(\.dismiss) private var dismiss
    @State private var lot: Lot
    @State private var printed: AddLotModel.PrintedDate
    @State private var choosingDate = false
    @State private var writeError: String?
    private let product: Product?
    private let inputs: RunwayInputs

    init(lot: Lot, product: Product?, inputs: RunwayInputs) {
        _lot = State(initialValue: lot)
        _printed = State(initialValue: lot.printedDate.map { .day($0) } ?? .none)
        self.product = product
        self.inputs = inputs
    }

    private var dateType: ShelfLifeDateType {
        product.flatMap { session.services.profiles[$0.shelfLifeProfileKey]?.dateType } ?? .bestBy
    }

    var body: some View {
        Form {
            Section("Dates") {
                Button {
                    choosingDate = true
                } label: {
                    LabeledContent("Printed date") {
                        Text(printed.date.map { "\(dateType.label) \($0.medium)" } ?? "No date")
                            .foregroundStyle(Color.hsInk2)
                    }
                }
                .foregroundStyle(Color.hsInk)
                DatePicker(
                    "Acquired",
                    selection: Binding(get: { lot.acquiredDate.pickerDate }, set: { lot.acquiredDate = CalendarDate(pickerDate: $0) }),
                    displayedComponents: .date)
            }
            Section {
                Picker("Location", selection: $lot.locationID) {
                    ForEach(LocationTree.paths(inputs.locations), id: \.last!.id) { path in
                        Text(path.map(\.name).joined(separator: " › ")).tag(path.last!.id)
                    }
                }
                Picker("Spot climate", selection: $lot.climateOverride) {
                    Text("Same as location").tag(ClimateClass?.none)
                    ForEach(ClimateClass.allCases, id: \.self) { Text($0.title).tag(Optional($0)) }
                }
                Picker("Packaging", selection: $lot.packaging) {
                    ForEach(Packaging.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Toggle("Opened", isOn: $lot.opened)
                TextField("Notes", text: Binding(get: { lot.notes ?? "" }, set: { lot.notes = $0 }), axis: .vertical)
            } header: {
                Text("Storage")
            } footer: {
                Text("Set a spot climate only when this item's spot differs from its room, like a box by the water heater.")
            }
        }
        .hearthList()
        .navigationTitle("Edit item")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("Save") { save() } }
        }
        .sheet(isPresented: $choosingDate) {
            PrintedDateSheet(printed: $printed, dateType: dateType, today: today.date)
        }
        .errorAlert($writeError)
    }

    private func save() {
        var saved = lot
        saved.printedDate = printed.date
        let notes = saved.notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        saved.notes = notes?.isEmpty == false ? notes : nil
        Task {
            do {
                try await session.services.lots.save(saved)
                dismiss()
            } catch {
                writeError = ErrorText.describe(error)
            }
        }
    }
}
