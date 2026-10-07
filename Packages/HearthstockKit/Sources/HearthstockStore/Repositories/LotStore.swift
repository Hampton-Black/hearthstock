import GRDB
import HearthstockCore

public struct GRDBLotRepository: LotRepository {
    /// Quantities within this of zero count as zero, so consuming 0.1 three times from 0.3 empties the lot
    /// instead of leaving 5e-17 behind.
    static let quantityTolerance = 1e-9

    private let database: AppDatabase
    private let clock: StoreClock

    public init(database: AppDatabase, clock: StoreClock = .system) {
        self.database = database
        self.clock = clock
    }

    public func list(siteID: SiteID, includeArchived: Bool) async throws -> [Lot] {
        try await database.writer.read { db in try Self.fetch(db, siteID: siteID, includeArchived: includeArchived) }
    }

    public func observeLots(siteID: SiteID) -> AsyncThrowingStream<[Lot], any Error> {
        database.observe { db in try Self.fetch(db, siteID: siteID, includeArchived: false) }
    }

    private static func fetch(_ db: Database, siteID: SiteID, includeArchived: Bool) throws -> [Lot] {
        var request = LotRecord.filter(Column("siteId") == siteID.stored)
        if !includeArchived {
            request = request.filter(Column("archived") == false)
        }
        return try request
            .order(Column("acquiredDate"), Column("createdAt"), Column("id"))
            .fetchAll(db)
            .map { try $0.toCore() }
    }

    public func save(_ lot: Lot) async throws {
        try await database.writer.write { [clock] db in
            try Self.save(lot, db: db, clock: clock)
        }
    }

    public func save(_ lot: Lot, newProduct product: Product) async throws {
        guard lot.productID == product.id else { throw RepositoryError.lotProductMismatch(lot.id, product.id) }
        try await database.writer.write { [clock] db in
            // Throwing anywhere in here rolls back the product insert too.
            try ProductRecord(product).insert(db, clock: clock)
            try Self.save(lot, db: db, clock: clock)
        }
    }

    public func delete(_ id: LotID) async throws {
        // The lot's shelf-life override goes with it (ON DELETE CASCADE).
        _ = try await database.writer.write { db in
            try LotRecord.deleteOne(db, key: id.stored)
        }
    }

    private static func save(_ lot: Lot, db: Database, clock: StoreClock) throws {
        guard let location = try LocationRecord.fetchOne(db, key: lot.locationID.stored) else {
            throw RepositoryError.locationNotFound(lot.locationID)
        }
        let siteID: SiteID = try ColumnDecoder(table: LocationRecord.databaseTableName)
            .id("siteId", location.siteId)
        try LotRecord(lot, siteID: siteID).save(db, clock: clock)
    }

    public func consume(_ id: LotID, amount: Double) async throws -> Lot {
        try await database.writer.write { [clock] db in
            guard amount.isFinite, amount > 0 else { throw RepositoryError.invalidAmount(amount) }
            guard var record = try LotRecord.fetchOne(db, key: id.stored) else {
                throw RepositoryError.lotNotFound(id)
            }
            guard !record.archived else { throw RepositoryError.lotArchived(id) }
            guard amount <= record.quantity + Self.quantityTolerance else {
                throw RepositoryError.insufficientQuantity(id, available: record.quantity, requested: amount)
            }
            let remaining = record.quantity - amount
            if remaining <= Self.quantityTolerance {
                record.quantity = 0
                record.archived = true
            } else {
                record.quantity = remaining
            }
            try record.update(db, clock: clock)
            return try record.toCore()
        }
    }

    public func archive(_ id: LotID) async throws {
        try await database.writer.write { [clock] db in
            guard var record = try LotRecord.fetchOne(db, key: id.stored) else {
                throw RepositoryError.lotNotFound(id)
            }
            record.archived = true
            try record.update(db, clock: clock)
        }
    }
}
