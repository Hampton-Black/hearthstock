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
    /// Setting a printed date clears `noPrintedDate`; a lot never has both.
    public var printedDate: CalendarDate? {
        didSet { if printedDate != nil { noPrintedDate = false } }
    }
    /// The package has no printed date, so a dated profile ages the lot from an estimate: the acquired date plus
    /// the profile's `rotationMonths`. Off means the date just hasn't been entered (the lot is flagged
    /// `missingDate`). Ticking it clears `printedDate`. Profiles with date type none ignore it.
    public var noPrintedDate: Bool {
        didSet { if noPrintedDate { printedDate = nil } }
    }
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
        noPrintedDate: Bool = false,
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
        // A printed date wins over the flag (didSet doesn't run in an initializer).
        self.noPrintedDate = printedDate == nil && noPrintedDate
        self.packaging = packaging
        self.locationID = locationID
        self.climateOverride = climateOverride
        self.notes = notes
        self.opened = opened
        self.archived = archived
    }
}

extension Lot {
    private enum CodingKeys: String, CodingKey {
        case id, productID, quantity, acquiredDate, printedDate, noPrintedDate, packaging, locationID, climateOverride
        case notes, opened, archived
    }

    /// `noPrintedDate` is optional in the encoding, so lots written before Slice 4 decode with it off.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(LotID.self, forKey: .id),
            productID: try container.decode(ProductID.self, forKey: .productID),
            quantity: try container.decode(Double.self, forKey: .quantity),
            acquiredDate: try container.decode(CalendarDate.self, forKey: .acquiredDate),
            printedDate: try container.decodeIfPresent(CalendarDate.self, forKey: .printedDate),
            noPrintedDate: try container.decodeIfPresent(Bool.self, forKey: .noPrintedDate) ?? false,
            packaging: try container.decode(Packaging.self, forKey: .packaging),
            locationID: try container.decode(LocationID.self, forKey: .locationID),
            climateOverride: try container.decodeIfPresent(ClimateClass.self, forKey: .climateOverride),
            notes: try container.decodeIfPresent(String.self, forKey: .notes),
            opened: try container.decode(Bool.self, forKey: .opened),
            archived: try container.decode(Bool.self, forKey: .archived))
    }
}
