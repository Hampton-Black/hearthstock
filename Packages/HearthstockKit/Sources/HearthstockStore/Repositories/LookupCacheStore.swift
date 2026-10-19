import GRDB
import HearthstockCore

public struct GRDBLookupCacheRepository: LookupCacheRepository {
    private let database: AppDatabase

    public init(database: AppDatabase) {
        self.database = database
    }

    public func get(_ barcode: Barcode) async throws -> CachedLookup? {
        try await database.writer.read { db in
            try LookupCacheRecord.fetchOne(db, key: barcode.rawValue)?.toCore()
        }
    }

    public func put(_ entry: CachedLookup) async throws {
        let record = try LookupCacheRecord(entry)
        try await database.writer.write { db in
            try record.upsert(db)
        }
    }

    public func count() async throws -> Int {
        try await database.writer.read { db in try LookupCacheRecord.fetchCount(db) }
    }

    public func clear() async throws {
        _ = try await database.writer.write { db in try LookupCacheRecord.deleteAll(db) }
    }
}
