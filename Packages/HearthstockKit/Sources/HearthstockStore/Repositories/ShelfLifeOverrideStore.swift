import Foundation
import GRDB
import HearthstockCore

public struct GRDBShelfLifeOverrideRepository: ShelfLifeOverrideRepository {
    private let database: AppDatabase
    private let clock: StoreClock

    public init(database: AppDatabase, clock: StoreClock = .system) {
        self.database = database
        self.clock = clock
    }

    public func override(for productID: ProductID) async throws -> ShelfLifeOverride? {
        try await database.writer.read { db in
            try ShelfLifeOverrideRecord.filter(Column("productId") == productID.stored).fetchOne(db)?.toCore()
        }
    }

    public func override(for lotID: LotID) async throws -> ShelfLifeOverride? {
        try await database.writer.read { db in
            try ShelfLifeOverrideRecord.filter(Column("lotId") == lotID.stored).fetchOne(db)?.toCore()
        }
    }

    public func save(_ override: ShelfLifeOverride, for productID: ProductID) async throws {
        try await database.writer.write { [clock] db in
            guard try ProductRecord.exists(db, key: productID.stored) else {
                throw RepositoryError.productNotFound(productID)
            }
            let existing = try ShelfLifeOverrideRecord.filter(Column("productId") == productID.stored).fetchOne(db)
            try Self.write(
                override, over: existing, db: db, clock: clock,
                record: { ShelfLifeOverrideRecord(override, id: $0, productID: productID) })
        }
    }

    public func save(_ override: ShelfLifeOverride, for lotID: LotID) async throws {
        try await database.writer.write { [clock] db in
            guard try LotRecord.exists(db, key: lotID.stored) else { throw RepositoryError.lotNotFound(lotID) }
            let existing = try ShelfLifeOverrideRecord.filter(Column("lotId") == lotID.stored).fetchOne(db)
            try Self.write(
                override, over: existing, db: db, clock: clock,
                record: { ShelfLifeOverrideRecord(override, id: $0, lotID: lotID) })
        }
    }

    public func clearOverride(for productID: ProductID) async throws {
        try await database.writer.write { db in
            _ = try ShelfLifeOverrideRecord.filter(Column("productId") == productID.stored).deleteAll(db)
        }
    }

    public func clearOverride(for lotID: LotID) async throws {
        try await database.writer.write { db in
            _ = try ShelfLifeOverrideRecord.filter(Column("lotId") == lotID.stored).deleteAll(db)
        }
    }

    /// Updates the owner's existing row in place (keeping its ID and `createdAt`) or inserts a new one; an empty
    /// override removes the row instead.
    private static func write(
        _ override: ShelfLifeOverride,
        over existing: ShelfLifeOverrideRecord?,
        db: Database,
        clock: StoreClock,
        record: (String) -> ShelfLifeOverrideRecord
    ) throws {
        if override.isEmpty {
            _ = try existing?.delete(db)
            return
        }
        if let existing {
            try record(existing.id).update(db, clock: clock)
        } else {
            try record(UUID().uuidString).insert(db, clock: clock)
        }
    }
}
