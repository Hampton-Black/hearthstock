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
    /// What the product form's picker shows ("Canned, low acid"). Required in the bundled table.
    public var name: String
    public var dateType: ShelfLifeDateType
    /// Months usable past the printed date.
    public var extensionMonths: Int?
    /// Months from the acquired date when packaging is Mylar + O2 or bucket.
    public var packagedLifeMonths: Int?
    /// Months from the acquired date when there's no printed date: the rotation interval for date type none, and
    /// the estimate for a best-by or use-by lot marked "no printed date". Required for dated profiles in a table
    /// loaded from JSON.
    public var rotationMonths: Int?

    public var id: ShelfLifeProfileKey { key }

    /// `name` defaults to the key, for profiles built in code.
    public init(
        key: ShelfLifeProfileKey,
        name: String? = nil,
        dateType: ShelfLifeDateType,
        extensionMonths: Int? = nil,
        packagedLifeMonths: Int? = nil,
        rotationMonths: Int? = nil
    ) {
        self.key = key
        self.name = name ?? key.rawValue
        self.dateType = dateType
        self.extensionMonths = extensionMonths
        self.packagedLifeMonths = packagedLifeMonths
        self.rotationMonths = rotationMonths
    }

    private enum CodingKeys: String, CodingKey {
        case key, name, dateType, extensionMonths, packagedLifeMonths, rotationMonths
    }

    /// A missing name decodes as empty, so the table can refuse it by key (`LoadError.missingName`).
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decode(ShelfLifeProfileKey.self, forKey: .key)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        dateType = try container.decode(ShelfLifeDateType.self, forKey: .dateType)
        extensionMonths = try container.decodeIfPresent(Int.self, forKey: .extensionMonths)
        packagedLifeMonths = try container.decodeIfPresent(Int.self, forKey: .packagedLifeMonths)
        rotationMonths = try container.decodeIfPresent(Int.self, forKey: .rotationMonths)
    }
}

/// A set of shelf-life profiles looked up by key. The bundled defaults are conservative and user-editable later.
public struct ShelfLifeProfileTable: Hashable, Sendable {
    public enum LoadError: Error, Equatable, CustomStringConvertible {
        case missingResource
        case duplicateKey(ShelfLifeProfileKey)
        /// Every profile needs a display name.
        case missingName(ShelfLifeProfileKey)
        /// A best-by or use-by profile needs `rotationMonths`, the estimate for lots with no printed date.
        case missingRotationMonths(ShelfLifeProfileKey)

        public var description: String {
            switch self {
            case .missingResource: "shelf-life-defaults.json isn't in the app bundle"
            case .duplicateKey(let key): "the shelf-life table lists \(key) twice"
            case .missingName(let key): "the shelf-life profile \(key) has no name"
            case .missingRotationMonths(let key): "the shelf-life profile \(key) has no rotationMonths"
            }
        }
    }

    /// In file order.
    public let profiles: [ShelfLifeProfile]
    private let byKey: [ShelfLifeProfileKey: ShelfLifeProfile]

    public init(profiles: [ShelfLifeProfile]) throws {
        var byKey: [ShelfLifeProfileKey: ShelfLifeProfile] = [:]
        for profile in profiles {
            guard !profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw LoadError.missingName(profile.key)
            }
            guard byKey.updateValue(profile, forKey: profile.key) == nil else {
                throw LoadError.duplicateKey(profile.key)
            }
        }
        self.profiles = profiles
        self.byKey = byKey
    }

    /// Decodes a JSON array of profiles: the bundled table, and later the user's edited copy. Every best-by and
    /// use-by profile must have `rotationMonths`, so a new one can't forget its estimate.
    public init(jsonData: Data) throws {
        try self.init(profiles: JSONDecoder().decode([ShelfLifeProfile].self, from: jsonData))
        if let undated = profiles.first(where: { $0.dateType != .none && $0.rotationMonths == nil }) {
            throw LoadError.missingRotationMonths(undated.key)
        }
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
