import Foundation
import GRDB
import HearthstockCore
import Testing
@testable import HearthstockStore

/// Exercises the `v1_initial` schema with raw SQL: constraints, triggers and cascades live in the
/// database, so these tests bypass the Swift layer on purpose.
@Suite struct SchemaTests {
    // MARK: - Seed

    /// Two sites, one location in each, and one product. Rows other tests build on.
    private func seededDatabase() throws -> AppDatabase {
        let db = try AppDatabase.inMemory()
        try db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO site (id, name) VALUES ('site-a', 'Main house'), ('site-b', 'Cabin');
                INSERT INTO location (id, siteId, name) VALUES
                    ('loc-a', 'site-a', 'Pantry'), ('loc-b', 'site-b', 'Cellar');
                INSERT INTO product (id, name, category, role, unitKind, shelfLifeProfileKey)
                    VALUES ('prod', 'Rice', 'food', 'supply', 'mass', 'dry-grain');
                """)
        }
        return db
    }

    private static let validLot = """
        INSERT INTO lot (id, siteId, productId, locationId, quantity, acquiredDate)
        VALUES ('lot-1', 'site-a', 'prod', 'loc-a', 20, '2026-01-31')
        """

    enum Failure: Sendable {
        case check, unique, foreignKey, trigger
        /// ON DELETE RESTRICT fires immediately and SQLite reports it with the trigger code.
        case restrict

        var code: ResultCode {
            switch self {
            case .check: .SQLITE_CONSTRAINT_CHECK
            case .unique: .SQLITE_CONSTRAINT_UNIQUE
            case .foreignKey: .SQLITE_CONSTRAINT_FOREIGNKEY
            case .trigger, .restrict: .SQLITE_CONSTRAINT_TRIGGER
            }
        }
    }

    struct BadWrite: Sendable, CustomTestStringConvertible {
        let label: String
        let sql: String
        let failure: Failure
        var testDescription: String { label }

        init(_ label: String, _ sql: String, _ failure: Failure = .check) {
            self.label = label
            self.sql = sql
            self.failure = failure
        }
    }

    private func expectRejected(_ write: BadWrite) throws {
        let db = try seededDatabase()
        try db.writer.write { try $0.execute(sql: Self.validLot) }
        do {
            try db.writer.write { try $0.execute(sql: write.sql) }
            Issue.record("accepted: \(write.label)")
        } catch let error as DatabaseError {
            #expect(error.extendedResultCode == write.failure.code, "\(write.label): \(error)")
            if write.failure == .restrict {
                #expect(error.message == "FOREIGN KEY constraint failed", "\(write.label): \(error)")
            }
        }
    }

    // MARK: - CHECK constraints

    static let badValues: [BadWrite] = [
        BadWrite("site: empty name", "INSERT INTO site (id, name) VALUES ('s', '')"),

        BadWrite("person: empty name",
                 "INSERT INTO person (id, siteId, name, kcalPerDay, waterGalPerDay) VALUES ('p', 'site-a', '', 2000, 1)"),
        BadWrite("person: negative kcal",
                 "INSERT INTO person (id, siteId, name, kcalPerDay, waterGalPerDay) VALUES ('p', 'site-a', 'Sam', -1, 1)"),
        BadWrite("person: negative water",
                 "INSERT INTO person (id, siteId, name, kcalPerDay, waterGalPerDay) VALUES ('p', 'site-a', 'Sam', 2000, -1)"),

        BadWrite("location: empty name", "INSERT INTO location (id, siteId, name) VALUES ('l', 'site-a', '')"),
        BadWrite("location: unknown climate class",
                 "INSERT INTO location (id, siteId, name, climateClass) VALUES ('l', 'site-a', 'Attic', 'tropical')"),
        BadWrite("location: unknown humidity",
                 "INSERT INTO location (id, siteId, name, humidity) VALUES ('l', 'site-a', 'Attic', 'damp')"),
        BadWrite("location: zero multiplier override",
                 "INSERT INTO location (id, siteId, name, climateMultiplierOverride) VALUES ('l', 'site-a', 'Attic', 0)"),
        BadWrite("location: negative multiplier override",
                 "INSERT INTO location (id, siteId, name, climateMultiplierOverride) VALUES ('l', 'site-a', 'Attic', -1)"),
        BadWrite("location: its own parent", "UPDATE location SET parentId = id WHERE id = 'loc-a'"),

        BadWrite("kit: counts flag not 0 or 1",
                 "INSERT INTO kit (id, homeSiteId, locationId, countsTowardSiteRunway) VALUES ('k', 'site-a', 'loc-a', 2)"),
        BadWrite("kit: impossible inspected date",
                 "INSERT INTO kit (id, homeSiteId, locationId, lastInspected) VALUES ('k', 'site-a', 'loc-a', '2026-02-30')"),
        BadWrite("kit: unpadded inspected date",
                 "INSERT INTO kit (id, homeSiteId, locationId, lastInspected) VALUES ('k', 'site-a', 'loc-a', '2026-2-3')"),

        BadWrite("product: empty name",
                 "INSERT INTO product (id, name, category, role, unitKind, shelfLifeProfileKey) VALUES ('p', '', 'food', 'supply', 'mass', 'k')"),
        BadWrite("product: unknown category",
                 "INSERT INTO product (id, name, category, role, unitKind, shelfLifeProfileKey) VALUES ('p', 'X', 'weapons', 'supply', 'mass', 'k')"),
        BadWrite("product: unknown role",
                 "INSERT INTO product (id, name, category, role, unitKind, shelfLifeProfileKey) VALUES ('p', 'X', 'food', 'boss', 'mass', 'k')"),
        BadWrite("product: unknown unit kind",
                 "INSERT INTO product (id, name, category, role, unitKind, shelfLifeProfileKey) VALUES ('p', 'X', 'food', 'supply', 'weight', 'k')"),
        BadWrite("product: empty barcode",
                 "INSERT INTO product (id, name, barcode, category, role, unitKind, shelfLifeProfileKey) VALUES ('p', 'X', '', 'food', 'supply', 'mass', 'k')"),
        BadWrite("product: empty profile key",
                 "INSERT INTO product (id, name, category, role, unitKind, shelfLifeProfileKey) VALUES ('p', 'X', 'food', 'supply', 'mass', '')"),
        BadWrite("product: negative kcal",
                 "INSERT INTO product (id, name, category, role, unitKind, kcalPerBaseUnit, shelfLifeProfileKey) VALUES ('p', 'X', 'food', 'supply', 'mass', -1, 'k')"),
        BadWrite("product: negative water",
                 "INSERT INTO product (id, name, category, role, unitKind, potableWaterGalPerBaseUnit, shelfLifeProfileKey) VALUES ('p', 'X', 'water', 'supply', 'volume', -1, 'k')"),

        BadWrite("lot: negative quantity", "UPDATE lot SET quantity = -0.5 WHERE id = 'lot-1'"),
        BadWrite("lot: impossible acquired date", "UPDATE lot SET acquiredDate = '2026-13-01' WHERE id = 'lot-1'"),
        BadWrite("lot: malformed printed date", "UPDATE lot SET printedDate = '01/31/2026' WHERE id = 'lot-1'"),
        BadWrite("lot: unknown packaging", "UPDATE lot SET packaging = 'tin' WHERE id = 'lot-1'"),
        BadWrite("lot: unknown climate override", "UPDATE lot SET climateOverride = 'tropical' WHERE id = 'lot-1'"),
        BadWrite("lot: opened not 0 or 1", "UPDATE lot SET opened = 2 WHERE id = 'lot-1'"),
        BadWrite("lot: archived not 0 or 1", "UPDATE lot SET archived = 2 WHERE id = 'lot-1'"),

        BadWrite("override: no target", "INSERT INTO shelf_life_override (id, extensionMonths) VALUES ('o', 6)"),
        BadWrite("override: two targets",
                 "INSERT INTO shelf_life_override (id, productId, lotId, extensionMonths) VALUES ('o', 'prod', 'lot-1', 6)"),
        BadWrite("override: unknown date type",
                 "INSERT INTO shelf_life_override (id, productId, dateType) VALUES ('o', 'prod', 'eatBy')"),
        BadWrite("override: negative extension",
                 "INSERT INTO shelf_life_override (id, productId, extensionMonths) VALUES ('o', 'prod', -1)"),
        BadWrite("override: negative packaged life",
                 "INSERT INTO shelf_life_override (id, productId, packagedLifeMonths) VALUES ('o', 'prod', -1)"),
        BadWrite("override: negative rotation",
                 "INSERT INTO shelf_life_override (id, productId, rotationMonths) VALUES ('o', 'prod', -1)"),
    ]

    @Test(arguments: badValues) func checkRejectsBadValue(_ write: BadWrite) throws {
        try expectRejected(write)
    }

    // MARK: - Uniqueness and foreign keys

    static let badReferences: [BadWrite] = [
        BadWrite("product: duplicate barcode",
                 """
                 INSERT INTO product (id, name, barcode, category, role, unitKind, shelfLifeProfileKey)
                 VALUES ('p1', 'A', '0123', 'food', 'supply', 'mass', 'k'), ('p2', 'B', '0123', 'food', 'supply', 'mass', 'k')
                 """, .unique),
        BadWrite("kit: second kit on a location",
                 """
                 INSERT INTO kit (id, homeSiteId, locationId) VALUES ('k1', 'site-a', 'loc-a'), ('k2', 'site-a', 'loc-a')
                 """, .unique),
        BadWrite("override: second override on a product",
                 """
                 INSERT INTO shelf_life_override (id, productId) VALUES ('o1', 'prod'), ('o2', 'prod')
                 """, .unique),
        BadWrite("override: second override on a lot",
                 """
                 INSERT INTO shelf_life_override (id, lotId) VALUES ('o1', 'lot-1'), ('o2', 'lot-1')
                 """, .unique),
        BadWrite("lot: unknown product",
                 """
                 INSERT INTO lot (id, siteId, productId, locationId, quantity, acquiredDate)
                 VALUES ('lot-2', 'site-a', 'nope', 'loc-a', 1, '2026-01-01')
                 """, .foreignKey),
        BadWrite("lot: unknown location",
                 """
                 INSERT INTO lot (id, siteId, productId, locationId, quantity, acquiredDate)
                 VALUES ('lot-2', 'site-a', 'prod', 'nope', 1, '2026-01-01')
                 """, .foreignKey),
        BadWrite("person: unknown site",
                 "INSERT INTO person (id, siteId, name, kcalPerDay, waterGalPerDay) VALUES ('p', 'nope', 'Sam', 2000, 1)",
                 .foreignKey),
        BadWrite("location: unknown parent",
                 "INSERT INTO location (id, siteId, name, parentId) VALUES ('l', 'site-a', 'Shelf', 'nope')", .foreignKey),
        BadWrite("kit: unknown location",
                 "INSERT INTO kit (id, homeSiteId, locationId) VALUES ('k', 'site-a', 'nope')", .foreignKey),
        BadWrite("delete product that still has lots", "DELETE FROM product WHERE id = 'prod'", .restrict),
        BadWrite("delete location that still has lots", "DELETE FROM location WHERE id = 'loc-a'", .restrict),
        BadWrite("delete site that still has locations", "DELETE FROM site WHERE id = 'site-b'", .restrict),
    ]

    @Test(arguments: badReferences) func uniquenessAndForeignKeysHold(_ write: BadWrite) throws {
        try expectRejected(write)
    }

    @Test func nullBarcodesDoNotCollide() throws {
        let db = try seededDatabase()
        try db.writer.write {
            try $0.execute(sql: """
                INSERT INTO product (id, name, category, role, unitKind, shelfLifeProfileKey)
                VALUES ('p1', 'A', 'food', 'supply', 'mass', 'k'), ('p2', 'B', 'food', 'supply', 'mass', 'k')
                """)
        }
    }

    @Test func deletingSiteCascadesItsPersonsOnly() throws {
        let db = try seededDatabase()
        try db.writer.write {
            try $0.execute(sql: """
                INSERT INTO site (id, name) VALUES ('site-c', 'Camp');
                INSERT INTO person (id, siteId, name, kcalPerDay, waterGalPerDay)
                    VALUES ('sam', 'site-c', 'Sam', 2000, 1), ('alex', 'site-a', 'Alex', 2000, 1);
                DELETE FROM site WHERE id = 'site-c';
                """)
        }
        let names = try db.writer.read { try String.fetchAll($0, sql: "SELECT name FROM person ORDER BY name") }
        #expect(names == ["Alex"])
    }

    @Test func deletingProductOrLotCascadesItsOverrides() throws {
        let db = try seededDatabase()
        try db.writer.write {
            try $0.execute(sql: Self.validLot)
            try $0.execute(sql: """
                INSERT INTO product (id, name, category, role, unitKind, shelfLifeProfileKey)
                    VALUES ('spare', 'Beans', 'food', 'supply', 'mass', 'k');
                INSERT INTO shelf_life_override (id, productId, extensionMonths) VALUES ('on-product', 'spare', 6);
                INSERT INTO shelf_life_override (id, lotId, rotationMonths) VALUES ('on-lot', 'lot-1', 12);
                """)
        }
        try db.writer.write { try $0.execute(sql: "DELETE FROM product WHERE id = 'spare'") }
        #expect(try db.writer.read { try String.fetchAll($0, sql: "SELECT id FROM shelf_life_override") } == ["on-lot"])
        try db.writer.write { try $0.execute(sql: "DELETE FROM lot WHERE id = 'lot-1'") }
        #expect(try db.writer.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM shelf_life_override") } == 0)
    }

    // MARK: - Site-consistency triggers

    static let siteMismatches: [BadWrite] = [
        BadWrite("lot insert: siteId differs from its location's",
                 """
                 INSERT INTO lot (id, siteId, productId, locationId, quantity, acquiredDate)
                 VALUES ('lot-2', 'site-b', 'prod', 'loc-a', 1, '2026-01-01')
                 """, .trigger),
        BadWrite("lot update: siteId changed away from its location's",
                 "UPDATE lot SET siteId = 'site-b' WHERE id = 'lot-1'", .trigger),
        BadWrite("lot update: moved to a location in another site",
                 "UPDATE lot SET locationId = 'loc-b' WHERE id = 'lot-1'", .trigger),
        BadWrite("location: site changed while it holds lots",
                 "UPDATE location SET siteId = 'site-b' WHERE id = 'loc-a'", .trigger),
        BadWrite("location insert: parent in another site",
                 "INSERT INTO location (id, siteId, name, parentId) VALUES ('l', 'site-a', 'Shelf', 'loc-b')", .trigger),
        BadWrite("location update: re-parented into another site",
                 """
                 INSERT INTO location (id, siteId, name) VALUES ('shelf', 'site-a', 'Shelf');
                 UPDATE location SET parentId = 'loc-b' WHERE id = 'shelf'
                 """, .trigger),
        BadWrite("kit insert: home site differs from its location's",
                 "INSERT INTO kit (id, homeSiteId, locationId) VALUES ('k', 'site-b', 'loc-a')", .trigger),
        BadWrite("kit update: home site changed away from its location's",
                 """
                 INSERT INTO kit (id, homeSiteId, locationId) VALUES ('k', 'site-a', 'loc-a');
                 UPDATE kit SET homeSiteId = 'site-b' WHERE id = 'k'
                 """, .trigger),
    ]

    static let siteChangeBlockers: [BadWrite] = [
        BadWrite("location: site changed while it has a child",
                 """
                 INSERT INTO location (id, siteId, name, parentId) VALUES ('shelf', 'site-a', 'Shelf', 'loc-a');
                 DELETE FROM lot;
                 UPDATE location SET siteId = 'site-b' WHERE id = 'loc-a'
                 """, .trigger),
        BadWrite("location: site changed while it is a kit",
                 """
                 INSERT INTO kit (id, homeSiteId, locationId) VALUES ('k', 'site-a', 'loc-a');
                 DELETE FROM lot;
                 UPDATE location SET siteId = 'site-b' WHERE id = 'loc-a'
                 """, .trigger),
    ]

    @Test(arguments: siteMismatches + siteChangeBlockers) func triggerRejectsSiteMismatch(_ write: BadWrite) throws {
        try expectRejected(write)
    }

    @Test func triggersAcceptConsistentWrites() throws {
        let db = try seededDatabase()
        try db.writer.write {
            try $0.execute(sql: Self.validLot)
            try $0.execute(sql: """
                INSERT INTO location (id, siteId, name, parentId) VALUES ('shelf', 'site-a', 'Top shelf', 'loc-a');
                UPDATE lot SET locationId = 'shelf', quantity = 12.5 WHERE id = 'lot-1';
                INSERT INTO kit (id, homeSiteId, locationId) VALUES ('k', 'site-a', 'shelf');
                UPDATE location SET siteId = 'site-a' WHERE id = 'loc-a';
                """)
        }
    }

    @Test func emptyLocationCanMoveSites() throws {
        let db = try seededDatabase()
        try db.writer.write { try $0.execute(sql: "UPDATE location SET siteId = 'site-a' WHERE id = 'loc-b'") }
    }

    // MARK: - Kit and location reference each other

    @Test func kitAndLocationInsertInEitherOrderWithinATransaction() throws {
        let db = try seededDatabase()
        try db.writer.write {
            try $0.execute(sql: """
                INSERT INTO location (id, siteId, name, kitId) VALUES ('bag', 'site-a', 'Go-bag', 'bag-kit');
                INSERT INTO kit (id, homeSiteId, locationId) VALUES ('bag-kit', 'site-a', 'bag');
                """)
            try $0.execute(sql: """
                INSERT INTO kit (id, homeSiteId, locationId) VALUES ('car-kit', 'site-a', 'loc-a');
                UPDATE location SET kitId = 'car-kit' WHERE id = 'loc-a';
                """)
        }
    }

    @Test func locationCannotCommitWithUnknownKit() throws {
        let db = try seededDatabase()
        #expect(throws: DatabaseError.self) {
            try db.writer.write {
                try $0.execute(sql: "INSERT INTO location (id, siteId, name, kitId) VALUES ('bag', 'site-a', 'Go-bag', 'ghost')")
            }
        }
        let count = try db.writer.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM location WHERE id = 'bag'") }
        #expect(count == 0)
    }

    // MARK: - Enum lists match Core

    /// A Core enum gaining a case must fail here, prompting a new migration; the shipped CHECK
    /// lists are frozen literals.
    @Test func checkListsAcceptEveryCoreCase() throws {
        let db = try seededDatabase()
        try db.writer.write { db in
            for (index, value) in ClimateClass.allCases.map(\.rawValue).enumerated() {
                try db.execute(sql: "INSERT INTO location (id, siteId, name, climateClass) VALUES (?, 'site-a', 'L', ?)",
                               arguments: ["climate-\(index)", value])
            }
            for (index, value) in Humidity.allCases.map(\.rawValue).enumerated() {
                try db.execute(sql: "INSERT INTO location (id, siteId, name, humidity) VALUES (?, 'site-a', 'L', ?)",
                               arguments: ["humidity-\(index)", value])
            }
            for (index, category) in Category.allCases.enumerated() {
                try db.execute(sql: """
                    INSERT INTO product (id, name, category, role, unitKind, shelfLifeProfileKey)
                    VALUES (?, 'P', ?, 'supply', 'mass', 'k')
                    """, arguments: ["category-\(index)", category.rawValue])
            }
            for (index, role) in ProductRole.allCases.enumerated() {
                try db.execute(sql: """
                    INSERT INTO product (id, name, category, role, unitKind, shelfLifeProfileKey)
                    VALUES (?, 'P', 'food', ?, 'mass', 'k')
                    """, arguments: ["role-\(index)", role.rawValue])
            }
            for (index, kind) in UnitKind.allCases.enumerated() {
                try db.execute(sql: """
                    INSERT INTO product (id, name, category, role, unitKind, shelfLifeProfileKey)
                    VALUES (?, 'P', 'food', 'supply', ?, 'k')
                    """, arguments: ["kind-\(index)", kind.rawValue])
            }
            for (index, packaging) in Packaging.allCases.enumerated() {
                try db.execute(sql: """
                    INSERT INTO lot (id, siteId, productId, locationId, quantity, acquiredDate, packaging)
                    VALUES (?, 'site-a', 'prod', 'loc-a', 1, '2026-01-01', ?)
                    """, arguments: ["packaging-\(index)", packaging.rawValue])
            }
            for (index, climate) in ClimateClass.allCases.enumerated() {
                try db.execute(sql: """
                    INSERT INTO lot (id, siteId, productId, locationId, quantity, acquiredDate, climateOverride)
                    VALUES (?, 'site-a', 'prod', 'loc-a', 1, '2026-01-01', ?)
                    """, arguments: ["override-\(index)", climate.rawValue])
            }
            for (index, dateType) in ShelfLifeDateType.allCases.enumerated() {
                try db.execute(sql: "INSERT INTO shelf_life_override (id, productId, dateType) VALUES (?, 'prod', ?)",
                               arguments: ["date-type-\(index)", dateType.rawValue])
                try db.execute(sql: "DELETE FROM shelf_life_override")
            }
        }
    }

    @Test(arguments: ["0001-01-01", "2024-02-29", "2026-12-31", "9999-12-31"])
    func calendarDatesAtBoundariesAreAccepted(_ date: String) throws {
        let db = try seededDatabase()
        try db.writer.write {
            try $0.execute(sql: """
                INSERT INTO lot (id, siteId, productId, locationId, quantity, acquiredDate, printedDate)
                VALUES ('lot-1', 'site-a', 'prod', 'loc-a', 0, ?, ?)
                """, arguments: [date, date])
        }
    }

    @Test(arguments: ["2025-02-29", "2026-04-31", "2026-00-10", "2026-01-00", "2026-1-01", "20260101", "2026-01-01T00:00:00Z"])
    func malformedOrImpossibleDatesAreRejected(_ date: String) throws {
        let db = try seededDatabase()
        #expect(throws: DatabaseError.self) {
            try db.writer.write {
                try $0.execute(sql: """
                    INSERT INTO lot (id, siteId, productId, locationId, quantity, acquiredDate)
                    VALUES ('lot-1', 'site-a', 'prod', 'loc-a', 1, ?)
                    """, arguments: [date])
            }
        }
    }

    // MARK: - Shape

    @Test func everyTableHasTimestampsThatDefaultToUTC() throws {
        let db = try seededDatabase()
        let tables = ["site", "person", "location", "kit", "product", "lot", "shelf_life_override"]
        try db.writer.read { db in
            for table in tables {
                let columns = try db.columns(in: table).map(\.name)
                #expect(columns.contains("createdAt") && columns.contains("updatedAt"), "\(table)")
            }
            let stamp = try String.fetchOne(db, sql: "SELECT createdAt FROM site WHERE id = 'site-a'")
            let utc = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/
            #expect(stamp?.wholeMatch(of: utc) != nil, "\(stamp ?? "nil")")
        }
    }

    @Test func requiredIndexesExist() throws {
        let db = try seededDatabase()
        let wanted: [(table: String, columns: [String])] = [
            ("lot", ["siteId", "archived"]), ("lot", ["productId"]), ("lot", ["locationId"]),
            ("location", ["siteId"]), ("product", ["barcode"]),
        ]
        try db.writer.read { db in
            for (table, columns) in wanted {
                let found = try db.indexes(on: table).contains { $0.columns == columns }
                #expect(found, "\(table)(\(columns.joined(separator: ", ")))")
            }
        }
    }

    @Test func foreignKeyCheckPassesOnSeededDatabase() throws {
        let db = try seededDatabase()
        try db.writer.write { try $0.execute(sql: Self.validLot) }
        try db.writer.read { try $0.checkForeignKeys() }
    }
}
