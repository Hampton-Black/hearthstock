import GRDB
import HearthstockCore

public struct GRDBProductRepository: ProductRepository {
    private let database: AppDatabase
    private let clock: StoreClock

    public init(database: AppDatabase, clock: StoreClock = .system) {
        self.database = database
        self.clock = clock
    }

    public func get(_ id: ProductID) async throws -> Product? {
        try await database.writer.read { db in
            try ProductRecord.fetchOne(db, key: id.stored)?.toCore()
        }
    }

    public func find(barcode: String) async throws -> Product? {
        try await database.writer.read { db in
            try ProductRecord.filter(Column("barcode") == barcode).fetchOne(db)?.toCore()
        }
    }

    public func search(name: String) async throws -> [Product] {
        try await database.writer.read { db in
            var request = ProductRecord.all()
            if !name.isEmpty {
                // SQLite's LIKE ignores case for ASCII only; `%` and `_` in the query are matched literally.
                let escaped = name
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "%", with: "\\%")
                    .replacingOccurrences(of: "_", with: "\\_")
                request = request.filter(sql: "name LIKE ? ESCAPE '\\'", arguments: ["%\(escaped)%"])
            }
            return try request.order(Column("name"), Column("id")).fetchAll(db).map { try $0.toCore() }
        }
    }

    public func listByRecentUse() async throws -> [Product] {
        try await database.writer.read { db in
            try ProductRecord.fetchAll(db, sql: """
                SELECT product.* FROM product
                LEFT JOIN (SELECT productId, MAX(createdAt) AS lastLot FROM lot GROUP BY productId) AS used
                    ON used.productId = product.id
                ORDER BY MAX(product.updatedAt, COALESCE(used.lastLot, '')) DESC, product.name, product.id
                """).map { try $0.toCore() }
        }
    }

    public func hasLots(_ id: ProductID) async throws -> Bool {
        try await database.writer.read { db in
            try LotRecord.filter(Column("productId") == id.stored).fetchCount(db) > 0
        }
    }

    public func save(_ product: Product) async throws {
        try await database.writer.write { [clock] db in
            if let existing = try ProductRecord.fetchOne(db, key: product.id.stored),
               existing.unitKind != product.unitKind.rawValue,
               try LotRecord.filter(Column("productId") == existing.id).fetchCount(db) > 0
            {
                throw RepositoryError.unitKindLocked(product.id)
            }
            try ProductRecord(product).save(db, clock: clock)
        }
    }
}
