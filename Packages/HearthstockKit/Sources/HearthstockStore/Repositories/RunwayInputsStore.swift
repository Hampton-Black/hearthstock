import GRDB
import HearthstockCore

/// Rows come back in the same order as the repositories' `list` calls, so the calculator's `problems`
/// and missing-data lists are stable between runs.
public struct GRDBRunwayInputsLoader: RunwayInputsLoader {
    private let database: AppDatabase

    public init(database: AppDatabase) {
        self.database = database
    }

    public func load(siteID: SiteID) async throws -> RunwayInputs {
        try await database.writer.read { db in
            let key = siteID.stored
            guard let site = try SiteRecord.fetchOne(db, key: key) else {
                throw RepositoryError.siteNotFound(siteID)
            }
            return RunwayInputs(
                site: try site.toCore(),
                occupants: try PersonRecord.filter(Column("siteId") == key)
                    .order(Column("createdAt"), Column("name"), Column("id")).fetchAll(db)
                    .map { try $0.toCore() },
                lots: try LotRecord.filter(Column("siteId") == key && Column("archived") == false)
                    .order(Column("acquiredDate"), Column("createdAt"), Column("id")).fetchAll(db)
                    .map { try $0.toCore() },
                // Products belong to no site; the calculator looks up only those its lots use.
                products: try ProductRecord.order(Column("name"), Column("id")).fetchAll(db).map { try $0.toCore() },
                locations: try LocationRecord.filter(Column("siteId") == key).order(Column("name"), Column("id")).fetchAll(db)
                    .map { try $0.toCore() },
                kits: try KitRecord.filter(Column("homeSiteId") == key).order(Column("createdAt"), Column("id")).fetchAll(db)
                    .map { try $0.toCore() }
            )
        }
    }
}
