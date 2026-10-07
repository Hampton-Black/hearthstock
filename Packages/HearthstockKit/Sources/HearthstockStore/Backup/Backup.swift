import Foundation
import GRDB
import HearthstockCore

/// Why an import or restore was refused. Nothing is written in any of these cases.
public enum BackupError: Error, Hashable, Sendable, LocalizedError {
    /// Import only fills an empty database; this one already holds rows.
    case databaseNotEmpty
    /// The file's `formatVersion` isn't one this build reads.
    case unsupportedFormatVersion(Int)
    /// The file isn't a readable backup, or its rows break the schema's rules (a lot in a missing
    /// location, a duplicate ID). The message says what.
    case invalidDocument(String)

    public var errorDescription: String? {
        switch self {
        case .databaseNotEmpty:
            "The database already holds data, so the backup wasn't imported."
        case .unsupportedFormatVersion(let version):
            "This backup is format version \(version), which this version of the app can't read."
        case .invalidDocument(let reason):
            "This file isn't a readable backup: \(reason)."
        }
    }
}

/// Whole-database backup to and from one versioned JSON document.
///
/// Export reads one consistent snapshot. Import writes into an empty database inside a single
/// transaction, so a file that fails halfway leaves the database empty. Export → import → export
/// yields the same bytes apart from `exportedAt`: rows are ordered by ID, keys are sorted, and
/// creation and update timestamps are restored as stored.
public struct GRDBBackup: BackupService {
    private let database: AppDatabase
    private let clock: StoreClock

    public init(database: AppDatabase, clock: StoreClock = .system) {
        self.database = database
        self.clock = clock
    }

    /// The whole database as a JSON document, stamped with the clock's now.
    public func export() async throws -> Data {
        try BackupDocument.makeEncoder().encode(try await currentDocument(exportedAt: clock.now()))
    }

    public func matchesCurrentData(_ data: Data) async throws -> Bool {
        let file = try Self.decode(data)
        let current = try await currentDocument(exportedAt: file.exportedAt)
        return file.normalized() == current.normalized()
    }

    private func currentDocument(exportedAt: Date) async throws -> BackupDocument {
        try await database.writer.read { db in
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
    }

    /// Loads a document produced by `export()` into this database.
    /// - Throws: `BackupError.databaseNotEmpty`, `.unsupportedFormatVersion` or `.invalidDocument`.
    public func `import`(_ data: Data) async throws {
        let document = try Self.decode(data)
        let locations = try Self.parentsFirst(document.locations)
        do {
            try await database.writer.write { db in
                guard try Self.isEmpty(db) else { throw BackupError.databaseNotEmpty }
                try Self.insert(document, locations: locations, db: db)
            }
        } catch let error as DatabaseError {
            throw BackupError.invalidDocument(error.description)
        }
    }

    /// Erases every table and loads the document in one transaction. A file that can't be read, or whose rows
    /// the schema refuses, throws before commit and leaves the existing data untouched.
    /// - Throws: `BackupError.unsupportedFormatVersion` or `.invalidDocument`.
    public func restore(_ data: Data) async throws {
        let document = try Self.decode(data)
        let locations = try Self.parentsFirst(document.locations)
        do {
            try await database.writer.write { db in
                try Self.eraseAll(db)
                try Self.insert(document, locations: locations, db: db)
            }
        } catch let error as DatabaseError {
            throw BackupError.invalidDocument(error.description)
        }
    }

    public func summary(of data: Data) async throws -> BackupSummary {
        let document = try Self.decode(data)
        _ = try Self.parentsFirst(document.locations)
        return BackupSummary(
            formatVersion: document.formatVersion, exportedAt: document.exportedAt,
            siteNames: document.sites.map(\.name), people: document.people.count,
            locations: document.locations.count, products: document.products.count,
            lots: document.lots.filter { !$0.archived }.count, archivedLots: document.lots.filter(\.archived).count)
    }

    public func currentSummary() async throws -> BackupSummary {
        try await database.writer.read { db in
            BackupSummary(
                formatVersion: BackupDocument.currentFormatVersion, exportedAt: nil,
                siteNames: try GRDBSiteRepository.ordered(SiteRecord.all()).fetchAll(db).map(\.name),
                people: try PersonRecord.fetchCount(db), locations: try LocationRecord.fetchCount(db),
                products: try ProductRecord.fetchCount(db),
                lots: try LotRecord.filter(Column("archived") == false).fetchCount(db),
                archivedLots: try LotRecord.filter(Column("archived") == true).fetchCount(db))
        }
    }

    /// Parents before children. A location's `kitId` and a kit's location refer to each other; the schema
    /// checks the former at commit, so locations go in first.
    private static func insert(_ document: BackupDocument, locations: [LocationRecord], db: Database) throws {
        for record in document.sites { try record.insert(db) }
        for record in document.people { try record.insert(db) }
        for record in document.products { try record.insert(db) }
        for record in locations { try record.insert(db) }
        for record in document.kits { try record.insert(db) }
        for record in document.lots { try record.insert(db) }
        for record in document.shelfLifeOverrides { try record.insert(db) }
    }

    /// Children before parents. `ON DELETE RESTRICT` fires row by row, so the links between locations, and from
    /// locations to kits, are cleared before those rows go.
    private static func eraseAll(_ db: Database) throws {
        try db.execute(sql: """
            DELETE FROM shelf_life_override;
            DELETE FROM lot;
            UPDATE location SET parentId = NULL, kitId = NULL;
            DELETE FROM kit;
            DELETE FROM location;
            DELETE FROM person;
            DELETE FROM product;
            DELETE FROM site;
            """)
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
        guard BackupDocument.readableFormatVersions.contains(header.formatVersion) else {
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
