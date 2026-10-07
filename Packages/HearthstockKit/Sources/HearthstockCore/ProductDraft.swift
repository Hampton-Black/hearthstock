import Foundation

/// Why a product draft can't become a product yet.
public enum ProductDraftError: Error, Hashable, Sendable {
    case emptyName
    /// Calories must be a finite number of kcal, zero or more.
    case invalidCalories
    /// Potable water must be a finite number of gallons, zero or more.
    case invalidWater
    /// A package size must be a finite amount greater than zero, in a unit of the product's kind.
    case invalidPackageSize
}

/// A product's fields without an ID: what the Add flow holds for a new product until one save writes the product
/// and its first lot together (Slice 4's scanner fills the same draft from a barcode lookup).
public struct ProductDraft: Hashable, Sendable {
    public var name: String
    public var barcode: String?
    public var category: Category
    /// Fixed to supply in Slice 3.
    public var role: ProductRole
    public var unitKind: UnitKind
    public var kcalPerBaseUnit: Double?
    public var potableWaterGalPerBaseUnit: Double?
    public var shelfLifeProfileKey: ShelfLifeProfileKey

    public init(
        name: String = "",
        barcode: String? = nil,
        category: Category = .food,
        role: ProductRole = .supply,
        unitKind: UnitKind = .mass,
        kcalPerBaseUnit: Double? = nil,
        potableWaterGalPerBaseUnit: Double? = nil,
        shelfLifeProfileKey: ShelfLifeProfileKey? = nil
    ) {
        self.name = name
        self.barcode = barcode
        self.category = category
        self.role = role
        self.unitKind = unitKind
        self.kcalPerBaseUnit = kcalPerBaseUnit
        self.potableWaterGalPerBaseUnit = potableWaterGalPerBaseUnit
        self.shelfLifeProfileKey = shelfLifeProfileKey ?? Self.defaultProfileKey(for: category)
    }

    /// An existing product's fields, for editing.
    public init(_ product: Product) {
        self.init(
            name: product.name, barcode: product.barcode, category: product.category, role: product.role,
            unitKind: product.unitKind, kcalPerBaseUnit: product.kcalPerBaseUnit,
            potableWaterGalPerBaseUnit: product.potableWaterGalPerBaseUnit,
            shelfLifeProfileKey: product.shelfLifeProfileKey)
    }

    /// The product these fields describe, with a trimmed name, a blank barcode as none, and calories kept only
    /// for food and water only for water.
    public func product(id: ProductID = ProductID()) throws(ProductDraftError) -> Product {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { throw .emptyName }
        let kcal = category == .food ? kcalPerBaseUnit : nil
        if let kcal, !(kcal.isFinite && kcal >= 0) { throw .invalidCalories }
        let water = category == .water ? potableWaterGalPerBaseUnit : nil
        if let water, !(water.isFinite && water >= 0) { throw .invalidWater }
        let code = barcode?.trimmingCharacters(in: .whitespacesAndNewlines)
        return Product(
            id: id, name: trimmedName, barcode: code?.isEmpty == false ? code : nil, category: category, role: role,
            unitKind: unitKind, kcalPerBaseUnit: kcal, potableWaterGalPerBaseUnit: water,
            shelfLifeProfileKey: shelfLifeProfileKey)
    }

    /// Calories per base unit from a package's label (Decision 6): 32,600 kcal in a 20 lb bag is 1,630 kcal per
    /// lb; 3,600 kcal in a case of 12 cans is 300 kcal per item.
    public static func kcalPerBaseUnit(
        kcalPerPackage: Double, packageSize: Quantity, unitKind: UnitKind
    ) throws(ProductDraftError) -> Double {
        guard kcalPerPackage.isFinite, kcalPerPackage >= 0 else { throw .invalidCalories }
        guard packageSize.unit.kind == unitKind, packageSize.value.isFinite, packageSize.value > 0,
              let base = try? packageSize.inBaseUnit(), base.value > 0
        else { throw .invalidPackageSize }
        return kcalPerPackage / base.value
    }

    /// Water by volume is drinkable gallon for gallon unless marked not potable; anything else starts empty.
    public static func defaultPotableWaterGalPerBaseUnit(category: Category, unitKind: UnitKind) -> Double? {
        category == .water && unitKind == .volume ? 1 : nil
    }

    /// A conservative starting profile for a new product of `category`. Editable on the form.
    public static func defaultProfileKey(for category: Category) -> ShelfLifeProfileKey {
        switch category {
        case .food: "unknown_food"
        case .water: "bottled_water"
        case .medical: "medication"
        case .power, .tools, .hygiene, .other: "honey_salt_sugar"
        }
    }
}
