import HearthstockCore
import SwiftUI

/// Edit a lot's dates, place and notes. Quantity changes go through Use or Adjust; the product through Edit product.
struct LotEditForm: View {
    @Environment(AppSession.self) private var session
    @Environment(Today.self) private var today
    @Environment(\.dismiss) private var dismiss
    @State private var lot: Lot
    @State private var printed: AddLotModel.PrintedDate
    @State private var estimateMonths: Int?
    @State private var choosingDate = false
    @State private var writeError: String?
    private let product: Product?
    private let inputs: RunwayInputs

    init(lot: Lot, product: Product?, inputs: RunwayInputs) {
        _lot = State(initialValue: lot)
        _printed = State(initialValue: AddLotModel.PrintedDate(lot))
        _estimateMonths = State(initialValue: inputs.lotShelfLifeOverrides[lot.id]?.rotationMonths)
        self.product = product
        self.inputs = inputs
    }

    private var profile: ShelfLifeProfile? {
        product.flatMap { session.services.profiles[$0.shelfLifeProfileKey] }
    }

    /// The lot as it would be saved: these dates, and this estimate when it has no printed date.
    private func edited(months: Int?) -> (lot: Lot, override: ShelfLifeOverride) {
        var saved = lot
        saved.printedDate = printed.date
        saved.noPrintedDate = printed.isNoPrintedDate
        var override = inputs.lotShelfLifeOverrides[lot.id] ?? ShelfLifeOverride()
        override.rotationMonths = months
        return (saved, override)
    }

    private func estimate(months: Int?) -> CalendarDate? {
        var (saved, override) = edited(months: months)
        saved.printedDate = nil
        saved.noPrintedDate = true
        let products = product.map { [$0] } ?? []
        return LotStatusEvaluator.statuses(
            for: inputs.site, lots: [saved], products: products, locations: inputs.locations, kits: inputs.kits,
            productShelfLifeOverrides: inputs.productShelfLifeOverrides, lotShelfLifeOverrides: [saved.id: override],
            profiles: session.services.profiles, on: today.date
        ).first?.evaluation?.usableBy
    }

    var body: some View {
        Form {
            Section("Dates") {
                Button {
                    choosingDate = true
                } label: {
                    LabeledContent("Printed date") {
                        let text = PrintedDateText.row(
                            printed, profile: profile,
                            estimate: printed.isNoPrintedDate ? estimate(months: estimateMonths) : nil)
                        if PrintedDateText.isMissing(printed, profile: profile) {
                            HStack(spacing: 4) {
                                Image(systemName: "calendar.badge.exclamationmark")
                                Text(text)
                            }
                            .foregroundStyle(Color.hsAmber)
                        } else {
                            Text(text).foregroundStyle(Color.hsInk2)
                        }
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
            PrintedDateSheet(
                printed: $printed, estimateMonths: $estimateMonths, profile: profile, today: today.date,
                estimate: estimate(months:))
        }
        .errorAlert($writeError)
    }

    private func save() {
        var (saved, override) = edited(months: estimateMonths)
        let notes = saved.notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        saved.notes = notes?.isEmpty == false ? notes : nil
        let overrideChanged = override != (inputs.lotShelfLifeOverrides[lot.id] ?? ShelfLifeOverride())
        Task {
            do {
                try await session.services.lots.save(saved)
                // An empty override clears it, so going back to the profile's months removes the lot's own.
                if overrideChanged { try await session.services.shelfLifeOverrides.save(override, for: saved.id) }
                dismiss()
            } catch {
                writeError = ErrorText.describe(error)
            }
        }
    }
}
