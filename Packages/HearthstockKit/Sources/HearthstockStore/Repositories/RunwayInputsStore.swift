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
        try await database.writer.read { db in try Self.fetch(db, siteID: siteID) }
    }

    public func observeRunwayInputs(siteID: SiteID) -> AsyncThrowingStream<RunwayInputs, any Error> {
        database.observe { db in try Self.fetch(db, siteID: siteID) }
    }

    private static func fetch(_ db: Database, siteID: SiteID) throws -> RunwayInputs {

        let key = siteID.stored
        guard let site = try SiteRecord.fetchOne(db, key: key) else {
            throw RepositoryError.siteNotFound(siteID)
        }
        // Products belong to no site, so every product override loads. A lot's override loads with its lot,
        // which is why archived lots' are left behind.
        let decoder = ColumnDecoder(table: ShelfLifeOverrideRecord.databaseTableName)
        var productOverrides: [ProductID: ShelfLifeOverride] = [:]
        for record in try ShelfLifeOverrideRecord.filter(Column("productId") != nil).fetchAll(db) {
            let id: ProductID? = try decoder.optionalID("productId", record.productId)
            if let id { productOverrides[id] = try record.toCore() }
        }
        var lotOverrides: [LotID: ShelfLifeOverride] = [:]
        let lotOverrideRows = try ShelfLifeOverrideRecord.fetchAll(
            db,
            sql: """
                SELECT shelf_life_override.* FROM shelf_life_override
                JOIN lot ON lot.id = shelf_life_override.lotId
                WHERE lot.siteId = ? AND lot.archived = 0
                """,
            arguments: [key])
        for record in lotOverrideRows {
            let id: LotID? = try decoder.optionalID("lotId", record.lotId)
            if let id { lotOverrides[id] = try record.toCore() }
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
                .map { try $0.toCore() },
            productShelfLifeOverrides: productOverrides,
            lotShelfLifeOverrides: lotOverrides
        )
    }
}
