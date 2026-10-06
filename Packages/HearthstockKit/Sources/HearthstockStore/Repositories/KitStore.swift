import GRDB
import HearthstockCore

public struct GRDBKitRepository: KitRepository {
    private let database: AppDatabase
    private let clock: StoreClock

    public init(database: AppDatabase, clock: StoreClock = .system) {
        self.database = database
        self.clock = clock
    }

    public func list(siteID: SiteID) async throws -> [Kit] {
        try await database.writer.read { db in
            try KitRecord
                .filter(Column("homeSiteId") == siteID.stored)
                .order(Column("createdAt"), Column("id"))
                .fetchAll(db)
                .map { try $0.toCore() }
        }
    }

    public func save(_ kit: Kit) async throws {
        try await database.writer.write { [clock] db in
            guard var location = try LocationRecord.fetchOne(db, key: kit.locationID.stored) else {
                throw RepositoryError.locationNotFound(kit.locationID)
            }
            let siteID: SiteID = try ColumnDecoder(table: LocationRecord.databaseTableName)
                .id("siteId", location.siteId)

            // A kit moved to another location leaves its old location pointing at it; clear that first.
            if let previous = try KitRecord.fetchOne(db, key: kit.id.stored),
                previous.locationId != kit.locationID.stored,
                var oldLocation = try LocationRecord.fetchOne(db, key: previous.locationId),
                oldLocation.kitId == previous.id
            {
                oldLocation.kitId = nil
                try oldLocation.update(db, clock: clock)
            }

            try KitRecord(kit, homeSiteID: siteID).save(db, clock: clock)
            // location.kitId is the other half of the link; the foreign key is deferred so the order is free.
            location.kitId = kit.id.stored
            try location.update(db, clock: clock)
        }
    }
}
