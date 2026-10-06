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

    public func save(_ product: Product) async throws {
        try await database.writer.write { [clock] db in
            try ProductRecord(product).save(db, clock: clock)
        }
    }
}
