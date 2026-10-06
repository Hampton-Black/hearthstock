import Foundation

/// Drives which runway a product feeds.
public enum Category: String, Hashable, Sendable, Codable, CaseIterable {
    case food
    case water
    case power
    case medical
    case tools
    case hygiene
    case other
}

/// Whether a product is stock itself, unlocks stock (a filter, a stove), or is used up enabling it (tabs, absorbers).
public enum ProductRole: String, Hashable, Sendable, Codable, CaseIterable {
    case supply
    case capability
    case consumable
}

/// Names a shelf-life profile in the bundled (and user-editable) table.
public struct ShelfLifeProfileKey: RawRepresentable, Hashable, Sendable, Codable, ExpressibleByStringLiteral,
    CustomStringConvertible
{
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }

    public init(from decoder: any Decoder) throws {
        self.rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var description: String { rawValue }
}

/// A reusable definition of what something is. Quantities live on lots, in this product's base unit.
public struct Product: Hashable, Sendable, Codable, Identifiable {
    public let id: ProductID
    public var name: String
    public var barcode: String?
    public var category: Category
    public var role: ProductRole
    /// What lot quantities measure; lots store them in `baseUnit` (lb, gal, Wh, count).
    public var unitKind: UnitKind
    public var kcalPerBaseUnit: Double?
    public var potableWaterGalPerBaseUnit: Double?
    public var shelfLifeProfileKey: ShelfLifeProfileKey

    public var baseUnit: QuantityUnit { unitKind.baseUnit }

    public init(
        id: ProductID = ProductID(),
        name: String,
        barcode: String? = nil,
        category: Category,
        role: ProductRole,
        unitKind: UnitKind,
        kcalPerBaseUnit: Double? = nil,
        potableWaterGalPerBaseUnit: Double? = nil,
        shelfLifeProfileKey: ShelfLifeProfileKey
    ) {
        self.id = id
        self.name = name
        self.barcode = barcode
        self.category = category
        self.role = role
        self.unitKind = unitKind
        self.kcalPerBaseUnit = kcalPerBaseUnit
        self.potableWaterGalPerBaseUnit = potableWaterGalPerBaseUnit
        self.shelfLifeProfileKey = shelfLifeProfileKey
    }
}
