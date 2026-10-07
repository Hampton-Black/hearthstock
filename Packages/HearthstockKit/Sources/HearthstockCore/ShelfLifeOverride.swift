import Foundation

/// A user's edits to a shelf-life profile, for one product or one lot. A nil field defers to the next level
/// down, so overriding only `extensionMonths` keeps the rest of the default. Zero is a value: it removes an
/// extension, it doesn't defer.
public struct ShelfLifeOverride: Hashable, Sendable, Codable {
    /// Beware that `.none` here is `Optional.none` (defer); spell the date type `ShelfLifeDateType.none`.
    public var dateType: ShelfLifeDateType?
    public var extensionMonths: Int?
    public var packagedLifeMonths: Int?
    public var rotationMonths: Int?

    public init(
        dateType: ShelfLifeDateType? = nil,
        extensionMonths: Int? = nil,
        packagedLifeMonths: Int? = nil,
        rotationMonths: Int? = nil
    ) {
        self.dateType = dateType
        self.extensionMonths = extensionMonths
        self.packagedLifeMonths = packagedLifeMonths
        self.rotationMonths = rotationMonths
    }

    /// True when every field defers, so the override changes nothing.
    public var isEmpty: Bool {
        dateType == nil && extensionMonths == nil && packagedLifeMonths == nil && rotationMonths == nil
    }

    /// `profile` with each field this override sets replaced. The key never changes.
    func applied(to profile: ShelfLifeProfile) -> ShelfLifeProfile {
        ShelfLifeProfile(
            key: profile.key,
            dateType: dateType ?? profile.dateType,
            extensionMonths: extensionMonths ?? profile.extensionMonths,
            packagedLifeMonths: packagedLifeMonths ?? profile.packagedLifeMonths,
            rotationMonths: rotationMonths ?? profile.rotationMonths
        )
    }
}

/// Finds the profile a lot ages by: its own override, then its product's, then the bundled default by key.
/// Each field falls back individually.
public struct ShelfLifeProfileResolver: Sendable {
    public var table: ShelfLifeProfileTable
    public var productOverrides: [ProductID: ShelfLifeOverride]
    public var lotOverrides: [LotID: ShelfLifeOverride]

    public init(
        table: ShelfLifeProfileTable,
        productOverrides: [ProductID: ShelfLifeOverride] = [:],
        lotOverrides: [LotID: ShelfLifeOverride] = [:]
    ) {
        self.table = table
        self.productOverrides = productOverrides
        self.lotOverrides = lotOverrides
    }

    /// Nil when the product's key isn't in the table; overrides edit a default, they don't stand in for one.
    public func profile(for lot: Lot, product: Product) -> ShelfLifeProfile? {
        guard var profile = table[product.shelfLifeProfileKey] else { return nil }
        if let override = productOverrides[product.id] { profile = override.applied(to: profile) }
        if let override = lotOverrides[lot.id] { profile = override.applied(to: profile) }
        return profile
    }
}
