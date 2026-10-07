import Foundation

/// The on-disk shape of a backup: every table, as the records the store itself reads and writes.
/// Dates are ISO strings (calendar dates as `YYYY-MM-DD`, timestamps as UTC with milliseconds), and the
/// timestamps travel with the rows so a restore changes nothing. Add a field or table only with a new
/// `formatVersion`.
struct BackupDocument: Codable, Equatable {
    static let currentFormatVersion = 1

    var formatVersion: Int
    var exportedAt: Date
    var sites: [SiteRecord]
    var people: [PersonRecord]
    var products: [ProductRecord]
    var locations: [LocationRecord]
    var kits: [KitRecord]
    var lots: [LotRecord]
    var shelfLifeOverrides: [ShelfLifeOverrideRecord]

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
