import Foundation

/// The on-disk shape of a backup: every table, as the records the store itself reads and writes.
/// Dates are ISO strings (calendar dates as `YYYY-MM-DD`, timestamps as UTC with milliseconds), and the
/// timestamps travel with the rows so a restore changes nothing. Add a field or table only with a new
/// `formatVersion`.
struct BackupDocument: Codable, Equatable {
    /// 2 added `noticeWindowDays` to sites.
    static let currentFormatVersion = 2
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
        return copy
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
