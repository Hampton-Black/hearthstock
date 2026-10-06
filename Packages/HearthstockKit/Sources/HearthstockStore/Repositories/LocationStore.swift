import GRDB
import HearthstockCore

public struct GRDBLocationRepository: LocationRepository {
    private let database: AppDatabase
    private let clock: StoreClock

    public init(database: AppDatabase, clock: StoreClock = .system) {
        self.database = database
        self.clock = clock
    }

    public func list(siteID: SiteID) async throws -> [Location] {
        try await database.writer.read { db in
            try LocationRecord
                .filter(Column("siteId") == siteID.stored)
                .order(Column("name"), Column("id"))
                .fetchAll(db)
                .map { try $0.toCore() }
        }
    }

    public func save(_ location: Location) async throws {
        try await database.writer.write { [clock] db in
            try LocationRecord(location).save(db, clock: clock)
        }
    }

    public func delete(_ id: LocationID) async throws {
        try await database.writer.write { db in
            let key = id.stored
            if try LotRecord.filter(Column("locationId") == key).fetchCount(db) > 0 {
                throw RepositoryError.locationHasLots(id)
            }
            if try LocationRecord.filter(Column("parentId") == key).fetchCount(db) > 0 {
                throw RepositoryError.locationHasChildren(id)
            }
            if try KitRecord.filter(Column("locationId") == key).fetchCount(db) > 0 {
                throw RepositoryError.locationHasKit(id)
            }
            _ = try LocationRecord.deleteOne(db, key: key)
        }
    }
}
