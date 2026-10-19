import Foundation

/// The on-disk shape of a backup: every table, as the records the store itself reads and writes.
/// Dates are ISO strings (calendar dates as `YYYY-MM-DD`, timestamps as UTC with milliseconds), and the
/// timestamps travel with the rows so a restore changes nothing. Add a field or table only with a new
/// `formatVersion`.
struct BackupDocument: Codable, Equatable {
    /// 2 added `noticeWindowDays` to sites. 3 added `noPrintedDate` to lots and the `lookupCache` table.
    static let currentFormatVersion = 3
    /// Versions `import` and `restore` read. Fields a version lacks get the defaults its migration gave them.
    static let readableFormatVersions = 1...currentFormatVersion

    var formatVersion: Int
    var exportedAt: Date
    var sites: [SiteRecord]
    var people: [PersonRecord]
    var products: [ProductRecord]
    var locations: [LocationRecord]
    var kits: [KitRecord]
    var lots: [LotRecord]
    var shelfLifeOverrides: [ShelfLifeOverrideRecord]
    /// Saved Open Food Facts answers (Decision 8), so a restore onto a new phone doesn't send every barcode again.
    var lookupCache: [LookupCacheRecord]

    /// The same rows in ID order under the current format, so two documents compare by content alone. A version 1
    /// file's sites already decode with the default notice window, as the migration gave them.
    func normalized() -> BackupDocument {
        var copy = self
        copy.formatVersion = Self.currentFormatVersion
        copy.sites.sort { $0.id < $1.id }
        copy.people.sort { $0.id < $1.id }
        copy.products.sort { $0.id < $1.id }
        copy.locations.sort { $0.id < $1.id }
        copy.kits.sort { $0.id < $1.id }
        copy.lots.sort { $0.id < $1.id }
        copy.shelfLifeOverrides.sort { $0.id < $1.id }
        copy.lookupCache.sort { $0.barcode < $1.barcode }
        return copy
    }

    private enum CodingKeys: String, CodingKey {
        case formatVersion, exportedAt, sites, people, products, locations, kits, lots, shelfLifeOverrides
        case lookupCache
    }

    init(
        formatVersion: Int, exportedAt: Date, sites: [SiteRecord], people: [PersonRecord], products: [ProductRecord],
        locations: [LocationRecord], kits: [KitRecord], lots: [LotRecord], shelfLifeOverrides: [ShelfLifeOverrideRecord],
        lookupCache: [LookupCacheRecord]
    ) {
        self.formatVersion = formatVersion
        self.exportedAt = exportedAt
        self.sites = sites
        self.people = people
        self.products = products
        self.locations = locations
        self.kits = kits
        self.lots = lots
        self.shelfLifeOverrides = shelfLifeOverrides
        self.lookupCache = lookupCache
    }

    /// Versions 1 and 2 have no lookup cache; their lots decode with `noPrintedDate` off (`LotRecord`).
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try container.decode(Int.self, forKey: .formatVersion)
        exportedAt = try container.decode(Date.self, forKey: .exportedAt)
        sites = try container.decode([SiteRecord].self, forKey: .sites)
        people = try container.decode([PersonRecord].self, forKey: .people)
        products = try container.decode([ProductRecord].self, forKey: .products)
        locations = try container.decode([LocationRecord].self, forKey: .locations)
        kits = try container.decode([KitRecord].self, forKey: .kits)
        lots = try container.decode([LotRecord].self, forKey: .lots)
        shelfLifeOverrides = try container.decode([ShelfLifeOverrideRecord].self, forKey: .shelfLifeOverrides)
        lookupCache = try container.decodeIfPresent([LookupCacheRecord].self, forKey: .lookupCache) ?? []
    }

    /// Just enough to refuse a file from a different format before trying to read the rest of it.
    struct Header: Decodable {
        var formatVersion: Int
    }

    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(StoredTimestamp.string(from: date))
        }
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let string = try decoder.singleValueContainer().decode(String.self)
            guard let date = StoredTimestamp.date(from: string) else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: decoder.codingPath, debugDescription: "not an ISO 8601 timestamp: \(string)"))
            }
            return date
        }
        return decoder
    }
}
