import GRDB
import HearthstockCore

public struct GRDBSiteRepository: SiteRepository {
    private let database: AppDatabase
    private let clock: StoreClock

    public init(database: AppDatabase, clock: StoreClock = .system) {
        self.database = database
        self.clock = clock
    }

    public func list() async throws -> [Site] {
        try await database.writer.read { db in
            try Self.ordered(SiteRecord.all()).fetchAll(db).map { try $0.toCore() }
        }
    }

    public func get(_ id: SiteID) async throws -> Site? {
        try await database.writer.read { db in
            try SiteRecord.fetchOne(db, key: id.stored)?.toCore()
        }
    }

    public func save(_ site: Site) async throws {
        try await database.writer.write { [clock] db in
            try SiteRecord(site).save(db, clock: clock)
        }
    }

    public func ensureDefaultSite() async throws -> Site {
        try await database.writer.write { [clock] db in
            if let existing = try Self.ordered(SiteRecord.all()).fetchOne(db) {
                return try existing.toCore()
            }
            let site = Site(name: "Home")
            try SiteRecord(site).insert(db, clock: clock)
            return site
        }
    }

    /// Oldest first; name and id break ties between sites created in the same millisecond.
    static func ordered(_ request: QueryInterfaceRequest<SiteRecord>) -> QueryInterfaceRequest<SiteRecord> {
        request.order(Column("createdAt"), Column("name"), Column("id"))
    }
}
