import Foundation

/// How a lot is packed, which can switch it to a longer shelf-life profile.
public enum Packaging: String, Hashable, Sendable, Codable, CaseIterable {
    case none
    case mylarO2
    case bucket
    case stabilized
}

/// A specific quantity of a product, with its own dates and location.
public struct Lot: Hashable, Sendable, Codable, Identifiable {
    public let id: LotID
    public var productID: ProductID
    /// Amount in the product's base unit. Convert at entry with `Quantity.inBaseUnit()`.
    public var quantity: Double
    public var acquiredDate: CalendarDate
    public var printedDate: CalendarDate?
    public var packaging: Packaging
    public var locationID: LocationID
    /// For a spot that differs from its room; wins over the location chain.
    public var climateOverride: ClimateClass?
    public var notes: String?
    public var opened: Bool
    /// Set when the quantity reaches zero; kept for burn-rate history.
    public var archived: Bool

    public init(
        id: LotID = LotID(),
        productID: ProductID,
        quantity: Double,
        acquiredDate: CalendarDate,
        printedDate: CalendarDate? = nil,
        packaging: Packaging = .none,
        locationID: LocationID,
        climateOverride: ClimateClass? = nil,
        notes: String? = nil,
        opened: Bool = false,
        archived: Bool = false
    ) {
        self.id = id
        self.productID = productID
        self.quantity = quantity
        self.acquiredDate = acquiredDate
        self.printedDate = printedDate
        self.packaging = packaging
        self.locationID = locationID
        self.climateOverride = climateOverride
        self.notes = notes
        self.opened = opened
        self.archived = archived
    }
}
