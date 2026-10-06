import Foundation

/// What a printed date means for a kind of item.
public enum ShelfLifeDateType: String, Hashable, Sendable, Codable, CaseIterable {
    /// Quality date; usable past it by `extensionMonths`.
    case bestBy
    /// Safety date; no extension.
    case useBy
    /// Usually no printed date; ages from the acquired date by `rotationMonths`, if any.
    case none
}

/// How a kind of item ages. Months are at baseline climate (climate-controlled); evaluation scales them.
public struct ShelfLifeProfile: Hashable, Sendable, Codable, Identifiable {
    public let key: ShelfLifeProfileKey
    public var dateType: ShelfLifeDateType
    /// Months usable past the printed date.
    public var extensionMonths: Int?
    /// Months from the acquired date when packaging is Mylar + O2 or bucket.
    public var packagedLifeMonths: Int?
    /// Months from the acquired date when there's no printed date.
    public var rotationMonths: Int?

    public var id: ShelfLifeProfileKey { key }

    public init(
        key: ShelfLifeProfileKey,
        dateType: ShelfLifeDateType,
        extensionMonths: Int? = nil,
        packagedLifeMonths: Int? = nil,
        rotationMonths: Int? = nil
    ) {
        self.key = key
        self.dateType = dateType
        self.extensionMonths = extensionMonths
        self.packagedLifeMonths = packagedLifeMonths
        self.rotationMonths = rotationMonths
    }
}

/// A set of shelf-life profiles looked up by key. The bundled defaults are conservative and user-editable later.
public struct ShelfLifeProfileTable: Hashable, Sendable {
    public enum LoadError: Error, Equatable {
        case missingResource
        case duplicateKey(ShelfLifeProfileKey)
    }

    /// In file order.
    public let profiles: [ShelfLifeProfile]
    private let byKey: [ShelfLifeProfileKey: ShelfLifeProfile]

    public init(profiles: [ShelfLifeProfile]) throws {
        var byKey: [ShelfLifeProfileKey: ShelfLifeProfile] = [:]
        for profile in profiles {
            guard byKey.updateValue(profile, forKey: profile.key) == nil else {
                throw LoadError.duplicateKey(profile.key)
            }
        }
        self.profiles = profiles
        self.byKey = byKey
    }

    /// Decodes a JSON array of profiles.
    public init(jsonData: Data) throws {
        try self.init(profiles: JSONDecoder().decode([ShelfLifeProfile].self, from: jsonData))
    }

    /// The table shipped in `Resources/shelf-life-defaults.json`.
    public static func bundledDefaults() throws -> ShelfLifeProfileTable {
        guard let url = Bundle.module.url(forResource: "shelf-life-defaults", withExtension: "json") else {
            throw LoadError.missingResource
        }
        return try ShelfLifeProfileTable(jsonData: Data(contentsOf: url))
    }

    public subscript(key: ShelfLifeProfileKey) -> ShelfLifeProfile? { byKey[key] }
}
