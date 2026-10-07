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

    /// The printed date: not entered (saved as none, and flagged when the profile expects one), "No expiry", or a day.
    enum PrintedDate: Equatable {
        case unset
        case none
        case day(CalendarDate)

        var date: CalendarDate? {
            if case .day(let date) = self { date } else { nil }
        }
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

    init(services: AppServices, siteID: SiteID, today: CalendarDate) {
        self.services = services
        self.siteID = siteID
        self.today = today
        acquired = today
        lastUsedLocationID = Preferences.lastUsedLocation(siteID: siteID)
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
        guard let lot = makeLot(id: LotID()), let inputs, let productValue = previewProduct else { return nil }
        var products = inputs.products.filter { $0.id != productValue.id }
        products.append(productValue)
        return LotStatusEvaluator.statuses(
            for: inputs.site, lots: [lot], products: products, locations: inputs.locations, kits: inputs.kits,
            productShelfLifeOverrides: inputs.productShelfLifeOverrides, profiles: services.profiles, on: today
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
            packaging: packaging, locationID: locationID, notes: trimmedNotes.isEmpty ? nil : trimmedNotes,
            opened: opened)
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
        packaging = .none
        opened = false
        notes = ""
        draftProductID = ProductID()
    }
}
