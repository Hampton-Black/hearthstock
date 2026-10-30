import Foundation
import HearthstockCore

/// The Add sheet's state. A new product stays a `ProductDraft` until Save writes the product and its lot in one
/// transaction; Cancel discards it, so no orphan products are left behind.
@MainActor @Observable
final class AddLotModel: RunwayInputsModel {
    enum ProductChoice: Equatable {
        case existing(Product)
        case new(ProductDraft)

        var name: String {
            switch self {
            case .existing(let product): product.name
            case .new(let draft): draft.name
            }
        }

        var category: SupplyCategory {
            switch self {
            case .existing(let product): product.category
            case .new(let draft): draft.category
            }
        }

        var unitKind: UnitKind {
            switch self {
            case .existing(let product): product.unitKind
            case .new(let draft): draft.unitKind
            }
        }

        var profileKey: ShelfLifeProfileKey {
            switch self {
            case .existing(let product): product.shelfLifeProfileKey
            case .new(let draft): draft.shelfLifeProfileKey
            }
        }
    }

    /// The printed date: not entered yet (flagged as missing when the profile expects one), none on the package (aged
    /// from an estimate, Slice 4 Decision 1), or a day.
    enum PrintedDate: Equatable {
        case unset
        case noPrintedDate
        case day(CalendarDate)

        init(_ lot: Lot) {
            if let date = lot.printedDate {
                self = .day(date)
            } else {
                self = lot.noPrintedDate ? .noPrintedDate : .unset
            }
        }

        var date: CalendarDate? {
            if case .day(let date) = self { date } else { nil }
        }

        var isNoPrintedDate: Bool { self == .noPrintedDate }
    }

    var phase: FeedPhase = .loading
    var inputs: RunwayInputs?
    var today: CalendarDate

    var product: ProductChoice? { didSet { productChanged(from: oldValue) } }
    var amount: Double?
    var unit: QuantityUnit = .pound
    var usePacks = false
    var packs = 1
    var printed: PrintedDate = .unset
    /// This lot's own months for its estimate (a lot override of `rotationMonths`); nil uses the profile's.
    var estimateMonths: Int?
    var acquired: CalendarDate
    var packaging: Packaging = .none
    var locationID: LocationID?
    var opened = false
    var notes = ""

    /// The lot just saved, until the next save or reset; its status arrives with the subscription.
    private(set) var savedLotID: LotID?
    private(set) var locationPaths: [[Location]] = []
    private(set) var lastUsedLocationID: LocationID?

    private let services: AppServices
    private let siteID: SiteID
    /// The product ID a new draft will be saved under, so the preview and the save agree.
    private var draftProductID = ProductID()

    /// What a scan already decided: the product (existing, or a draft from a lookup), the location, and a note
    /// shown above the product row. The save path is the same as for manual entry.
    struct Preset {
        var product: ProductChoice?
        var locationID: LocationID?
        var note: String?
        /// The lookup the draft came from, so switching the unit kind can fill calories for the new unit.
        var lookedUp: LookedUpProduct?
        /// The profile the lookup's draft guessed from the name (Slice 5 Task 7).
        var guess: NameProfileGuesser.Guess?
        /// A new product already started on the not-found form, with its calorie answers and name guess. Takes the
        /// place of `product`.
        var newProduct: NewProductEntry?
    }

    /// Shown above the product row ("Filled in from Open Food Facts…") until the item is saved.
    private(set) var note: String?
    private(set) var lookedUp: LookedUpProduct?
    /// A new product's calorie answers and name guess, kept in step with `product`'s draft (Slice 5).
    private(set) var newEntry: NewProductEntry?

    init(services: AppServices, siteID: SiteID, today: CalendarDate, preset: Preset? = nil) {
        self.services = services
        self.siteID = siteID
        self.today = today
        acquired = today
        lastUsedLocationID = Preferences.lastUsedLocation(siteID: siteID)
        if let preset {
            locationID = preset.locationID
            note = preset.note
            lookedUp = preset.lookedUp
            if let started = preset.newProduct {
                newEntry = started
                product = .new(started.draft)
                amount = started.amount ?? amount
            } else {
                if case .new(let draft)? = preset.product {
                    newEntry = NewProductEntry(draft: draft, lookedUp: preset.lookedUp, guess: preset.guess)
                }
                product = preset.product
            }
            productChanged(from: nil)
        }
    }

    // MARK: Product

    /// A product picked or made in the picker: anything the scan said about the old one no longer applies.
    func choose(_ choice: ProductChoice) {
        note = nil
        lookedUp = nil
        if case .new(let draft) = choice {
            newEntry = NewProductEntry(draft: draft)
        } else {
            newEntry = nil
        }
        product = choice
    }

    /// The new product's draft as the product form handed it back.
    func formFinished(_ draft: ProductDraft) {
        guard var entry = newEntry else {
            product = .new(draft)
            return
        }
        entry.adopt(draft)
        newEntry = entry
        product = .new(entry.draft)
    }

    /// Changes the new product's calorie answers (Slice 5 Task 5). A bag's net weight can switch it to lb and scale
    /// the amount (Decision 8).
    func updateCalories(_ change: (inout CalorieEntry) -> Void) {
        guard var entry = newEntry else { return }
        entry.amount = amount
        entry.updateCalories(change)
        newEntry = entry
        product = .new(entry.draft)
        // A switch or a new net weight gives the amount in the base unit (lb, gal, items).
        if entry.amount != amount {
            amount = entry.amount
            unit = entry.draft.unitKind.baseUnit
        }
    }

    /// "Change" on the name guess.
    func pickProfile(_ key: ShelfLifeProfileKey) {
        guard var entry = newEntry else { return }
        entry.pickProfile(key)
        newEntry = entry
        product = .new(entry.draft)
    }

    func recompute() {
        locationPaths = LocationTree.paths(inputs?.locations ?? [])
        let ids = Set(locationPaths.map { $0.last!.id })
        if let id = locationID, !ids.contains(id) { locationID = nil }
        if locationID == nil {
            locationID = lastUsedLocationID.flatMap { ids.contains($0) ? $0 : nil } ?? locationPaths.first?.last?.id
        }
    }

    private func productChanged(from old: ProductChoice?) {
        guard let product, product.unitKind != old?.unitKind else { return }
        unit = product.unitKind.baseUnit
        if product.unitKind == .count, amount == nil { amount = 1 }
    }

    // MARK: Derived

    var entry: QuantityEntry? {
        guard let amount else { return nil }
        return QuantityEntry(value: amount, unit: unit, packs: usePacks ? packs : nil)
    }

    /// The amount that will be stored, in the product's base unit.
    var baseAmount: Double? {
        guard let product, let entry else { return nil }
        return try? entry.baseAmount(for: product.unitKind)
    }

    /// "24 × 0.5 L = 3.17 gal"
    var storedAmountText: String? {
        guard let product, let entry, let base = baseAmount else { return nil }
        let typed = QuantityText.format(entry.value, entry.unit)
        let stored = QuantityText.format(base, product.unitKind.baseUnit)
        if usePacks { return "\(packs) × \(typed) = \(stored)" }
        return entry.unit == product.unitKind.baseUnit ? nil : "\(typed) = \(stored)"
    }

    var profile: ShelfLifeProfile? { product.flatMap { services.profiles[$0.profileKey] } }

    var canSave: Bool { product != nil && baseAmount != nil && locationID != nil }

    /// What the lot would be today, before it's saved.
    var preview: LotStatus? {
        guard let lot = makeLot(id: LotID()) else { return nil }
        return status(of: lot, estimateMonths: estimateMonths)
    }

    /// The estimated usable-by date if this lot were marked "no printed date", with `months` (nil: the profile's).
    func estimateUsableBy(months: Int?) -> CalendarDate? {
        guard var lot = makeLot(id: LotID()) else { return nil }
        lot.noPrintedDate = true
        return status(of: lot, estimateMonths: months)?.evaluation?.usableBy
    }

    /// The lot's state today if `date` were its printed date (the date sheet's live preview).
    func stateIfPrinted(_ date: CalendarDate) -> LotState? {
        guard var lot = makeLot(id: LotID()) else { return nil }
        lot.printedDate = date
        return status(of: lot, estimateMonths: nil)?.state
    }

    private func status(of lot: Lot, estimateMonths: Int?) -> LotStatus? {
        guard let inputs, let productValue = previewProduct else { return nil }
        var products = inputs.products.filter { $0.id != productValue.id }
        products.append(productValue)
        let overrides = estimateMonths.map { [lot.id: ShelfLifeOverride(rotationMonths: $0)] } ?? [:]
        return LotStatusEvaluator.statuses(
            for: inputs.site, lots: [lot], products: products, locations: inputs.locations, kits: inputs.kits,
            productShelfLifeOverrides: inputs.productShelfLifeOverrides, lotShelfLifeOverrides: overrides,
            profiles: services.profiles, on: today
        ).first
    }

    /// The saved lot as the database now has it.
    var savedStatus: LotStatus? {
        guard let savedLotID, let inputs else { return nil }
        return LotStatusEvaluator.statuses(for: inputs, profiles: services.profiles, on: today)
            .first { $0.id == savedLotID }
    }

    private var previewProduct: Product? {
        switch product {
        case .existing(let product): product
        case .new(let draft): try? draft.product(id: draftProductID)
        case nil: nil
        }
    }

    private var productID: ProductID? {
        switch product {
        case .existing(let product): product.id
        case .new: draftProductID
        case nil: nil
        }
    }

    private func makeLot(id: LotID) -> Lot? {
        guard let productID, let base = baseAmount, let locationID else { return nil }
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return Lot(
            id: id, productID: productID, quantity: base, acquiredDate: acquired, printedDate: printed.date,
            noPrintedDate: printed.isNoPrintedDate, packaging: packaging, locationID: locationID,
            notes: trimmedNotes.isEmpty ? nil : trimmedNotes, opened: opened)
    }

    // MARK: Save

    /// Writes the lot (and the new product with it), then clears what belongs to this item. Location and
    /// acquired date stay for the next entry.
    func save() async throws {
        guard let product, let lot = makeLot(id: LotID()) else { return }
        switch product {
        case .existing:
            try await services.lots.save(lot)
        case .new(let draft):
            try await services.lots.save(lot, newProduct: try draft.product(id: draftProductID))
        }
        if printed.isNoPrintedDate, let estimateMonths {
            try await services.shelfLifeOverrides.save(ShelfLifeOverride(rotationMonths: estimateMonths), for: lot.id)
        }
        Preferences.setLastUsedLocation(lot.locationID, siteID: siteID)
        lastUsedLocationID = lot.locationID
        savedLotID = lot.id
        resetItem()
    }

    func resetItem() {
        product = nil
        amount = nil
        usePacks = false
        packs = 1
        printed = .unset
        estimateMonths = nil
        note = nil
        lookedUp = nil
        newEntry = nil
        packaging = .none
        opened = false
        notes = ""
        draftProductID = ProductID()
    }
}
