import Foundation
import GRDB
import HearthstockCore

/// One saved lookup answer. `product` is the `LookedUpProduct` as JSON text (sorted keys, so a backup round-trip is
/// byte for byte). No `createdAt`/`updatedAt`: `fetchedAt` is the row's only time, and a refresh replaces the row.
struct LookupCacheRecord: Codable, FetchableRecord, PersistableRecord, Equatable, Sendable {
    static let databaseTableName = "lookup_cache"

    var barcode: String
    var outcome: String
    var product: String?
    var fetchedAt: Date

    static func databaseDateEncodingStrategy(for column: String) -> DatabaseDateEncodingStrategy {
        .custom { StoredTimestamp.string(from: $0) }
    }

    static func databaseDateDecodingStrategy(for column: String) -> DatabaseDateDecodingStrategy {
        .custom { dbValue in String.fromDatabaseValue(dbValue).flatMap(StoredTimestamp.date(from:)) }
    }

    init(_ entry: CachedLookup) throws {
        barcode = entry.barcode.rawValue
        fetchedAt = entry.fetchedAt
        switch entry.outcome {
        case .found(let product):
            outcome = "found"
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            self.product = String(decoding: try encoder.encode(product), as: UTF8.self)
        case .notFound:
            outcome = "notFound"
            product = nil
        }
    }

    func toCore() throws -> CachedLookup {
        let code: Barcode
        do {
            code = try Barcode(barcode)
        } catch {
            throw RecordMappingError(table: Self.databaseTableName, column: "barcode", value: barcode)
        }
        switch (outcome, product) {
        case ("found", let json?):
            guard let decoded = try? JSONDecoder().decode(LookedUpProduct.self, from: Data(json.utf8)) else {
                throw RecordMappingError(table: Self.databaseTableName, column: "product", value: json)
            }
            return CachedLookup(barcode: code, outcome: .found(decoded), fetchedAt: fetchedAt)
        case ("notFound", nil):
            return CachedLookup(barcode: code, outcome: .notFound, fetchedAt: fetchedAt)
        default:
            throw RecordMappingError(table: Self.databaseTableName, column: "outcome", value: outcome)
        }
    }
}
