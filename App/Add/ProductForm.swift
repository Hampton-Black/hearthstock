import HearthstockCore
import SwiftUI

/// The product form's state: the draft plus the per-package helper's inputs (Decision 6). Only the per-base-unit
/// value reaches the draft.
@MainActor @Observable
final class ProductFormModel {
    var draft: ProductDraft
    var perPackage = false
    var kcalPerPackage: Double?
    var packageSize: Double?
    var packageUnit: QuantityUnit
    var notPotable: Bool
    /// True when the product has lots, so its unit kind is fixed.
    var unitKindLocked = false

    init(draft: ProductDraft) {
        self.draft = draft
        packageUnit = draft.unitKind.baseUnit
        notPotable = draft.category == .water && draft.potableWaterGalPerBaseUnit == nil
    }

    func setCategory(_ category: SupplyCategory) {
        let oldDefault = ProductDraft.defaultProfileKey(for: draft.category)
        draft.category = category
        if draft.shelfLifeProfileKey == oldDefault {
            draft.shelfLifeProfileKey = ProductDraft.defaultProfileKey(for: category)
        }
        if category == .water && draft.unitKind == .mass { setUnitKind(.volume) }
        resetWater()
    }

    func setUnitKind(_ kind: UnitKind) {
        guard !unitKindLocked else { return }
        draft.unitKind = kind
        packageUnit = kind.baseUnit
        resetWater()
    }

    func setNotPotable(_ value: Bool) {
        notPotable = value
        draft.potableWaterGalPerBaseUnit = value
            ? nil : ProductDraft.defaultPotableWaterGalPerBaseUnit(category: draft.category, unitKind: draft.unitKind)
    }

    private func resetWater() {
        guard draft.category == .water else { return }
        notPotable = false
        draft.potableWaterGalPerBaseUnit = ProductDraft.defaultPotableWaterGalPerBaseUnit(
            category: draft.category, unitKind: draft.unitKind)
    }

    /// The per-package helper's result, when its inputs make one.
    var helperKcalPerBaseUnit: Double? {
        guard perPackage, let kcalPerPackage, let packageSize else { return nil }
        return try? ProductDraft.kcalPerBaseUnit(
            kcalPerPackage: kcalPerPackage, packageSize: Quantity(value: packageSize, unit: packageUnit),
            unitKind: draft.unitKind)
    }

    /// The draft with the helper applied.
    func finishedDraft() throws(ProductDraftError) -> ProductDraft {
        var result = draft
        if perPackage, draft.category == .food {
            guard let kcalPerPackage, let packageSize else { throw .invalidPackageSize }
            result.kcalPerBaseUnit = try ProductDraft.kcalPerBaseUnit(
                kcalPerPackage: kcalPerPackage, packageSize: Quantity(value: packageSize, unit: packageUnit),
                unitKind: draft.unitKind)
        }
        _ = try result.product()
        return result
    }
}

/// Create or edit a product. New from the Add flow: Save hands the draft back (Task 8 saves product and lot
/// together). Editing an existing product: Save writes it.
struct ProductForm: View {
    enum Mode {
        case new(onDone: (ProductDraft) -> Void)
        case edit(Product)
    }

    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var model: ProductFormModel
    @State private var writeError: String?
    private let mode: Mode

    init(draft: ProductDraft, onDone: @escaping (ProductDraft) -> Void) {
        _model = State(initialValue: ProductFormModel(draft: draft))
        mode = .new(onDone: onDone)
    }

    init(editing product: Product) {
        _model = State(initialValue: ProductFormModel(draft: ProductDraft(product)))
        mode = .edit(product)
    }

    private var isEditing: Bool {
        if case .edit = mode { true } else { false }
    }

    var body: some View {
        @Bindable var model = model
        Form {
            if isEditing {
                Section {
                    Label("Changes apply to every lot of this product.", systemImage: "exclamationmark.triangle")
                        .font(.subheadline)
                        .foregroundStyle(Color.hsAmber)
                        .listRowBackground(Color.hsAmberBg)
                }
            }
            Section {
                LabeledContent("Name") {
                    TextField("Long-grain white rice", text: $model.draft.name).multilineTextAlignment(.trailing)
                }
                Picker("Category", selection: Binding(get: { model.draft.category }, set: { model.setCategory($0) })) {
                    ForEach(SupplyCategory.allCases, id: \.self) { Label($0.title, systemImage: $0.symbol).tag($0) }
                }
            }

            Section {
                Picker("Measured by", selection: Binding(get: { model.draft.unitKind }, set: { model.setUnitKind($0) })) {
                    ForEach(UnitKind.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .disabled(model.unitKindLocked)
            } header: {
                Text("Measured by")
            } footer: {
                if model.unitKindLocked {
                    Text("Fixed: this product already has lots stored in \(model.draft.unitKind.perUnit).")
                } else if model.draft.unitKind == .count {
                    Text("Lots are counted in items (cans, jars, MREs).")
                } else {
                    Text("Lots are stored in \(model.draft.unitKind.baseUnit.symbol). Any \(model.draft.unitKind.title.lowercased()) unit works when adding.")
                }
            }

            if model.draft.category == .food { caloriesSection }
            if model.draft.category == .water { waterSection }

            Section {
                Picker("Profile", selection: $model.draft.shelfLifeProfileKey) {
                    ForEach(session.services.profiles.profiles) { Text($0.name).tag($0.key) }
                }
            } header: {
                Text("Shelf life")
            } footer: {
                if let profile = session.services.profiles[model.draft.shelfLifeProfileKey] {
                    Text(ProfileText.summary(profile))
                }
            }

            Section {
                LabeledContent("Barcode") {
                    TextField("Optional", text: Binding(get: { model.draft.barcode ?? "" }, set: { model.draft.barcode = $0 }))
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .hearthList()
        .navigationTitle(isEditing ? "Edit product" : "New product")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(model.draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .task {
            if case .edit(let product) = mode {
                model.unitKindLocked = (try? await session.services.products.hasLots(product.id)) ?? true
            }
        }
        .errorAlert($writeError)
    }

    private var caloriesSection: some View {
        @Bindable var model = model
        let per = model.draft.unitKind.perUnit
        return Section {
            if model.perPackage {
                LabeledContent("kcal per package") {
                    TextField("32,600", value: $model.kcalPerPackage, format: .number)
                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing).numeric()
                }
                LabeledContent("Package size") {
                    HStack(spacing: 6) {
                        TextField("20", value: $model.packageSize, format: .number)
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing).numeric()
                        if model.draft.unitKind == .count {
                            Text("items").foregroundStyle(Color.hsInk2)
                        } else {
                            Picker("Unit", selection: $model.packageUnit) {
                                ForEach(QuantityUnit.entryUnits(for: model.draft.unitKind), id: \.self) {
                                    Text($0.symbol).tag($0)
                                }
                            }
                            .labelsHidden()
                            .fixedSize()
                        }
                    }
                }
                if let value = model.helperKcalPerBaseUnit {
                    Text("= \(Amount.text(value, fraction: 1)) kcal per \(per)")
                        .font(.headline).foregroundStyle(Color.hsTint).numeric()
                }
            } else {
                LabeledContent("kcal per \(per)") {
                    TextField("Unknown", value: $model.draft.kcalPerBaseUnit, format: .number)
                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing).numeric()
                }
            }
            Toggle("Enter per package", isOn: $model.perPackage)
        } header: {
            Text("Calories")
        } footer: {
            Text(model.perPackage
                ? "From the nutrition label: servings × kcal per serving, then the package size. Only the per-\(per) number is saved."
                : "Leave empty if you don't know yet; the Dashboard lists products missing calories.")
        }
    }

    private var waterSection: some View {
        @Bindable var model = model
        return Section {
            Toggle("Not potable", isOn: Binding(get: { model.notPotable }, set: { model.setNotPotable($0) }))
            if !model.notPotable && model.draft.unitKind != .volume {
                LabeledContent("Drinkable gal per \(model.draft.unitKind.perUnit)") {
                    TextField("0.5", value: $model.draft.potableWaterGalPerBaseUnit, format: .number)
                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing).numeric()
                }
            }
        } header: {
            Text("Drinking water")
        } footer: {
            Text(model.notPotable
                ? "Rain barrels, water heaters and pools are shown beside your water runway, not in it, until you have a way to treat them."
                : model.draft.unitKind == .volume ? "Counts gallon for gallon toward water runway." : "How many gallons one item holds.")
        }
    }

    private func save() {
        let draft: ProductDraft
        do {
            draft = try model.finishedDraft()
        } catch {
            writeError = ProfileText.describe(error)
            return
        }
        switch mode {
        case .new(let onDone):
            onDone(draft)
            dismiss()
        case .edit(let product):
            Task {
                do {
                    try await session.services.products.save(try draft.product(id: product.id))
                    dismiss()
                } catch {
                    writeError = ErrorText.describe(error)
                }
            }
        }
    }
}

enum ProfileText {
    /// "Usable 24 months past best-by, or 10 years in Mylar or a bucket."
    static func summary(_ profile: ShelfLifeProfile) -> String {
        var parts: [String] = []
        switch profile.dateType {
        case .bestBy:
            let months = profile.extensionMonths ?? 0
            parts.append(months > 0 ? "Usable \(duration(months)) past best-by" : "Usable until its best-by date")
        case .useBy:
            parts.append("Use-by date: no use past it")
        case .none:
            if let rotation = profile.rotationMonths {
                parts.append("Rotate every \(duration(rotation)) from when it was stored")
            } else {
                parts.append("Doesn't expire")
            }
        }
        if let packaged = profile.packagedLifeMonths {
            parts.append("or \(duration(packaged)) in Mylar or a bucket")
        }
        return parts.joined(separator: ", ") + ". Times are for a climate-controlled room; the location's climate scales them."
    }

    static func duration(_ months: Int) -> String {
        if months % 12 == 0 && months >= 24 { return "\(months / 12) years" }
        return months == 1 ? "1 month" : "\(months) months"
    }

    static func describe(_ error: ProductDraftError) -> String {
        switch error {
        case .emptyName: "Give the product a name."
        case .invalidCalories: "Calories must be a number, zero or more."
        case .invalidWater: "Drinkable water must be a number of gallons, zero or more."
        case .invalidPackageSize: "Enter the calories and a package size greater than zero."
        }
    }
}
