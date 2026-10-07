import Foundation
import GRDB

/// Why an import was refused. Nothing is written in any of these cases.
public enum BackupError: Error, Hashable, Sendable {
    /// Import only fills an empty database; this one already holds rows.
    case databaseNotEmpty
    /// The file's `formatVersion` isn't one this build reads.
    case unsupportedFormatVersion(Int)
    /// The file isn't a readable backup, or its rows break the schema's rules (a lot in a missing
    /// location, a duplicate ID). The message says what.
    case invalidDocument(String)
}

/// Whole-database backup to and from one versioned JSON document.
///
/// Export reads one consistent snapshot. Import writes into an empty database inside a single
/// transaction, so a file that fails halfway leaves the database empty. Export → import → export
/// yields the same bytes apart from `exportedAt`: rows are ordered by ID, keys are sorted, and
/// creation and update timestamps are restored as stored.
public struct GRDBBackup: Sendable {
    private let database: AppDatabase
    private let clock: StoreClock

    public init(database: AppDatabase, clock: StoreClock = .system) {
        self.database = database
        self.clock = clock
    }

    /// The whole database as a JSON document, stamped with the clock's now.
    public func export() async throws -> Data {
        let exportedAt = clock.now()
        let document = try await database.writer.read { db in
            BackupDocument(
                formatVersion: BackupDocument.currentFormatVersion,
                exportedAt: exportedAt,
                sites: try SiteRecord.order(Column("id")).fetchAll(db),
                people: try PersonRecord.order(Column("id")).fetchAll(db),
                products: try ProductRecord.order(Column("id")).fetchAll(db),
                locations: try LocationRecord.order(Column("id")).fetchAll(db),
                kits: try KitRecord.order(Column("id")).fetchAll(db),
                lots: try LotRecord.order(Column("id")).fetchAll(db),
                shelfLifeOverrides: try ShelfLifeOverrideRecord.order(Column("id")).fetchAll(db)
            )
        }
        return try BackupDocument.makeEncoder().encode(document)
    }

    /// Loads a document produced by `export()` into this database.
    /// - Throws: `BackupError.databaseNotEmpty`, `.unsupportedFormatVersion` or `.invalidDocument`.
    public func `import`(_ data: Data) async throws {
        let document = try Self.decode(data)
        let locations = try Self.parentsFirst(document.locations)
        do {
            try await database.writer.write { db in
                guard try Self.isEmpty(db) else { throw BackupError.databaseNotEmpty }
                // Parents before children. A location's `kitId` and a kit's location refer to each other;
                // the schema checks the former at commit, so locations go in first.
                for record in document.sites { try record.insert(db) }
                for record in document.people { try record.insert(db) }
                for record in document.products { try record.insert(db) }
                for record in locations { try record.insert(db) }
                for record in document.kits { try record.insert(db) }
                for record in document.lots { try record.insert(db) }
                for record in document.shelfLifeOverrides { try record.insert(db) }
            }
        } catch let error as DatabaseError {
            throw BackupError.invalidDocument(error.description)
        }
    }

    private static let tables = [
        "site", "person", "product", "location", "kit", "lot", "shelf_life_override",
    ]

    private static func isEmpty(_ db: Database) throws -> Bool {
        for table in tables where try Row.fetchOne(db, sql: "SELECT 1 FROM \(table) LIMIT 1") != nil {
            return false
        }
        return true
    }

    private static func decode(_ data: Data) throws -> BackupDocument {
        let decoder = BackupDocument.makeDecoder()
        let header: BackupDocument.Header
        do {
            header = try decoder.decode(BackupDocument.Header.self, from: data)
        } catch {
            throw BackupError.invalidDocument("not a Hearthstock backup: \(describe(error))")
        }
        guard header.formatVersion == BackupDocument.currentFormatVersion else {
            throw BackupError.unsupportedFormatVersion(header.formatVersion)
        }
        do {
            return try decoder.decode(BackupDocument.self, from: data)
        } catch {
            throw BackupError.invalidDocument(describe(error))
        }
    }

    private static func describe(_ error: any Error) -> String {
        guard let error = error as? DecodingError else { return "\(error)" }
        switch error {
        case .keyNotFound(let key, _): return "missing \(key.stringValue)"
        case .typeMismatch(_, let context), .valueNotFound(_, let context), .dataCorrupted(let context):
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            return path.isEmpty ? context.debugDescription : "\(path): \(context.debugDescription)"
        @unknown default: return "\(error)"
        }
    }

    /// Orders locations so each follows its parent (the parent foreign key is checked row by row).
    private static func parentsFirst(_ locations: [LocationRecord]) throws -> [LocationRecord] {
        var ordered: [LocationRecord] = []
        var placed: Set<String> = []
        var remaining = locations
        while !remaining.isEmpty {
            let ready = remaining.filter { $0.parentId.map(placed.contains) ?? true }
            guard !ready.isEmpty else {
                throw BackupError.invalidDocument("locations form a cycle or name a parent that isn't in the file")
            }
            ordered += ready
            placed.formUnion(ready.map(\.id))
            remaining.removeAll { placed.contains($0.id) }
        }
        return ordered
    }
}
