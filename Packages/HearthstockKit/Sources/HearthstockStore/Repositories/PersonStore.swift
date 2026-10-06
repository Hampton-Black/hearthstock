import GRDB
import HearthstockCore

public struct GRDBPersonRepository: PersonRepository {
    private let database: AppDatabase
    private let clock: StoreClock

    public init(database: AppDatabase, clock: StoreClock = .system) {
        self.database = database
        self.clock = clock
    }

    public func list(siteID: SiteID) async throws -> [Person] {
        try await database.writer.read { db in
            try PersonRecord
                .filter(Column("siteId") == siteID.stored)
                .order(Column("createdAt"), Column("name"), Column("id"))
                .fetchAll(db)
                .map { try $0.toCore() }
        }
    }

    public func save(_ person: Person) async throws {
        try await database.writer.write { [clock] db in
            try PersonRecord(person).save(db, clock: clock)
        }
    }

    public func delete(_ id: PersonID) async throws {
        _ = try await database.writer.write { db in
            try PersonRecord.deleteOne(db, key: id.stored)
        }
    }
}
