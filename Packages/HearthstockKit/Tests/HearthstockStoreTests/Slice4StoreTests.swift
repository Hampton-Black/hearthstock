import Foundation
import GRDB
import HearthstockCore
import Synchronization
import Testing
@testable import HearthstockStore

private let t0 = Date(timeIntervalSince1970: 1_767_225_600)
private func day(_ iso: String) -> CalendarDate { CalendarDate(iso: iso)! }

/// One in-memory database with the Slice 4 repositories, seeded with a site, a pantry and a product.
private struct World {
    let db: AppDatabase
    let site: Site
    let pantry: Location
    let rice: Product
    let products: GRDBProductRepository
    let lots: GRDBLotRepository
    let cache: GRDBLookupCacheRepository
    let backup: GRDBBackup

    init() async throws {
        let db = try AppDatabase.inMemory()
        let ticks = Mutex(0)
        let clock = StoreClock { t0.addingTimeInterval(Double(ticks.withLock { $0 += 1; return $0 })) }
        self.db = db
        products = GRDBProductRepository(database: db, clock: clock)
        lots = GRDBLotRepository(database: db, clock: clock)
        cache = GRDBLookupCacheRepository(database: db)
        backup = GRDBBackup(database: db, clock: clock)
        site = try await GRDBSiteRepository(database: db, clock: clock).ensureDefaultSite()
        pantry = Location(siteID: site.id, name: "Pantry")
        try await GRDBLocationRepository(database: db, clock: clock).save(pantry)
        rice = Product(
            name: "Rice", barcode: "0036000291452", category: .food, role: .supply, unitKind: .mass,
            kcalPerBaseUnit: 1600, shelfLifeProfileKey: "white_rice")
        try await products.save(rice)
    }

    func lot(quantity: Double = 10, printed: String? = nil, noPrintedDate: Bool = false) -> Lot {
        Lot(productID: rice.id, quantity: quantity, acquiredDate: day("2026-01-01"), printedDate: printed.map(day),
            noPrintedDate: noPrintedDate, locationID: pantry.id)
    }

    func stored(_ id: LotID) async throws -> Lot? {
        try await lots.list(siteID: site.id, includeArchived: true).first { $0.id == id }
    }
}

// MARK: - Barcodes

@Suite struct BarcodeStoreTests {
    @Test func aUPCAFindsTheProductSavedWithItsEAN13FormAndBack() async throws {
        let world = try await World()
        #expect(try await world.products.find(barcode: "036000291452") == world.rice)
        #expect(try await world.products.find(barcode: "0036000291452") == world.rice)
        #expect(try await world.products.find(barcode: "0 36000 29145 2") == world.rice)
        #expect(try await world.products.find(barcode: "4006381333931") == nil)
    }

    @Test func aCodeThatCantBeNormalizedIsMatchedExactly() async throws {
        let world = try await World()
        let legacy = Product(
            name: "Legacy", barcode: "123", category: .food, role: .supply, unitKind: .count,
            shelfLifeProfileKey: "unknown_food")
        try await world.products.save(legacy)
        #expect(try await world.products.find(barcode: "123") == legacy)
    }

    /// Products written before Slice 4, then migrated.
    @Test func theBarcodeMigrationNormalizesWhatItCanAndKeepsTheRest() throws {
        let queue = try DatabaseQueue(configuration: AppDatabase.makeConfiguration())
        try AppDatabase.migrator.migrate(queue, upTo: "v2_site_notice_window")
        try queue.write { db in
            for (id, barcode) in [
                ("a-upca", "036000291452"),  // → 0036000291452
                ("b-upce", "04252614"),  // UPC-E typed as is → 0042100005264
                ("c-ean13", "4006381333931"),  // already normalized
                ("d-invalid", "123"),  // kept
                ("e-held", "0012345000065"),  // already the normalized form of …
                ("f-collides", "012345000065"),  // … this one, which therefore stays as it is
                ("g-none", nil),
            ] as [(String, String?)] {
                try db.execute(sql: """
                    INSERT INTO product (id, name, barcode, category, role, unitKind, shelfLifeProfileKey)
                    VALUES (?, 'P', ?, 'food', 'supply', 'count', 'unknown_food')
                    """, arguments: [id, barcode])
            }
        }
        try AppDatabase.migrator.migrate(queue)
        let barcodes = try queue.read { db in
            try Row.fetchAll(db, sql: "SELECT id, barcode FROM product ORDER BY id")
                .map { ($0["id"] as String, $0["barcode"] as String?) }
        }
        #expect(barcodes.map(\.0) == ["a-upca", "b-upce", "c-ean13", "d-invalid", "e-held", "f-collides", "g-none"])
        #expect(barcodes.map(\.1) == [
            "0036000291452", "0042100005264", "4006381333931", "123", "0012345000065", "012345000065", nil,
        ])
    }
}

// MARK: - No printed date

@Suite struct NoPrintedDateStoreTests {
    @Test func theFlagRoundTripsThroughTheRepository() async throws {
        let world = try await World()
        let lot = world.lot(noPrintedDate: true)
        try await world.lots.save(lot)
        #expect(try await world.stored(lot.id)?.noPrintedDate == true)

        var dated = try #require(try await world.stored(lot.id))
        dated.printedDate = day("2027-01-01")
        try await world.lots.save(dated)
        let back = try #require(try await world.stored(lot.id))
        #expect(!back.noPrintedDate)
        #expect(back.printedDate == day("2027-01-01"))
    }

    @Test func theSchemaRefusesAPrintedDateAndTheFlagTogether() async throws {
        let world = try await World()
        #expect(throws: DatabaseError.self) {
            try world.db.writer.write { db in
                try db.execute(sql: """
                    INSERT INTO lot (id, siteId, productId, locationId, quantity, acquiredDate, printedDate, noPrintedDate)
                    VALUES (?, ?, ?, ?, 1, '2026-01-01', '2027-01-01', 1)
                    """, arguments: [LotID().stored, world.site.id.stored, world.rice.id.stored, world.pantry.id.stored])
            }
        }
    }

    @Test func existingLotsMigrateWithTheFlagOff() throws {
        let queue = try DatabaseQueue(configuration: AppDatabase.makeConfiguration())
        try AppDatabase.migrator.migrate(queue, upTo: "v3_normalize_barcodes")
        try queue.write { db in
            try db.execute(sql: """
                INSERT INTO site (id, name) VALUES ('s', 'Home');
                INSERT INTO location (id, siteId, name) VALUES ('l', 's', 'Pantry');
                INSERT INTO product (id, name, category, role, unitKind, shelfLifeProfileKey)
                    VALUES ('p', 'Beans', 'food', 'supply', 'count', 'canned_low_acid');
                INSERT INTO lot (id, siteId, productId, locationId, quantity, acquiredDate)
                    VALUES ('undated', 's', 'p', 'l', 6, '2026-01-01');
                INSERT INTO lot (id, siteId, productId, locationId, quantity, acquiredDate, printedDate)
                    VALUES ('dated', 's', 'p', 'l', 6, '2026-01-01', '2027-01-01');
                """)
        }
        try AppDatabase.migrator.migrate(queue)
        let flags = try queue.read { try Int.fetchAll($0, sql: "SELECT noPrintedDate FROM lot ORDER BY id") }
        #expect(flags == [0, 0])
    }
}

// MARK: - Lookup cache

@Suite struct LookupCacheStoreTests {
    static let soup = LookedUpProduct(
        name: "Cream Of Mushroom Soup", brand: "Campbell's", quantityLabel: "10.5 oz (298 g)", netQuantity: 297.67,
        netQuantityUnit: .gram, kcalPer100: 83.33, kcalPerServing: 100, categoryTags: ["en:canned-foods"])
    static let soupCode = try! Barcode("051000012616")
    static let jugCode = try! Barcode("060823858011")

    @Test func foundAndNotFoundRoundTrip() async throws {
        let world = try await World()
        let found = CachedLookup(barcode: Self.soupCode, outcome: .found(Self.soup), fetchedAt: t0)
        let notFound = CachedLookup(barcode: Self.jugCode, outcome: .notFound, fetchedAt: t0.addingTimeInterval(1.5))
        try await world.cache.put(found)
        try await world.cache.put(notFound)
        #expect(try await world.cache.get(Self.soupCode) == found)
        #expect(try await world.cache.get(Self.jugCode) == notFound)
        #expect(try await world.cache.get(try Barcode("4006381333931")) == nil)
        #expect(try await world.cache.count() == 2)
    }

    @Test func putReplacesAndClearEmpties() async throws {
        let world = try await World()
        try await world.cache.put(CachedLookup(barcode: Self.soupCode, outcome: .notFound, fetchedAt: t0))
        let refreshed = CachedLookup(barcode: Self.soupCode, outcome: .found(Self.soup), fetchedAt: t0.addingTimeInterval(60))
        try await world.cache.put(refreshed)
        #expect(try await world.cache.get(Self.soupCode) == refreshed)
        #expect(try await world.cache.count() == 1)
        try await world.cache.clear()
        #expect(try await world.cache.count() == 0)
        #expect(try await world.cache.get(Self.soupCode) == nil)
    }

    @Test func theSchemaRefusesAFoundRowWithoutAProduct() async throws {
        let world = try await World()
        #expect(throws: DatabaseError.self) {
            try world.db.writer.write { db in
                try db.execute(sql: "INSERT INTO lookup_cache (barcode, outcome, product, fetchedAt) VALUES ('1', 'found', NULL, 'x')")
            }
        }
    }
}

// MARK: - Backup format 3

@Suite struct Slice4BackupTests {
    @Test func theFlagAndTheCacheSurviveExportAndRestore() async throws {
        let world = try await World()
        let lot = world.lot(noPrintedDate: true)
        try await world.lots.save(lot)
        let found = CachedLookup(barcode: LookupCacheStoreTests.soupCode, outcome: .found(LookupCacheStoreTests.soup), fetchedAt: t0)
        try await world.cache.put(found)
        try await world.cache.put(CachedLookup(barcode: LookupCacheStoreTests.jugCode, outcome: .notFound, fetchedAt: t0))
        let data = try await world.backup.export()

        let target = try AppDatabase.inMemory()
        try await GRDBBackup(database: target).restore(data)
        let lots = try await GRDBLotRepository(database: target).list(siteID: world.site.id, includeArchived: true)
        #expect(lots.first { $0.id == lot.id }?.noPrintedDate == true)
        let cache = GRDBLookupCacheRepository(database: target)
        #expect(try await cache.count() == 2)
        #expect(try await cache.get(LookupCacheStoreTests.soupCode) == found)
        #expect(try await GRDBBackup(database: target).matchesCurrentData(data))
    }

    @Test func aRestoreReplacesTheCache() async throws {
        let world = try await World()
        let data = try await world.backup.export()  // no cache entries
        try await world.cache.put(CachedLookup(barcode: LookupCacheStoreTests.jugCode, outcome: .notFound, fetchedAt: t0))
        try await world.backup.restore(data)
        #expect(try await world.cache.count() == 0)
    }

    @Test func aVersion2BackupImportsWithTheFlagOffAndAnEmptyCache() async throws {
        let world = try await World()
        try await world.lots.save(world.lot())
        var document = try #require(JSONSerialization.jsonObject(with: try await world.backup.export()) as? [String: Any])
        document["formatVersion"] = 2
        document["lookupCache"] = nil
        document["lots"] = (document["lots"] as? [[String: Any]])?.map { lot in
            var lot = lot
            lot["noPrintedDate"] = nil
            return lot
        }
        let data = try JSONSerialization.data(withJSONObject: document)

        let target = try AppDatabase.inMemory()
        try await GRDBBackup(database: target).import(data)
        let lots = try await GRDBLotRepository(database: target).list(siteID: world.site.id, includeArchived: true)
        #expect(lots.count == 1)
        #expect(lots.allSatisfy { !$0.noPrintedDate })
        #expect(try await GRDBLookupCacheRepository(database: target).count() == 0)
    }

    @Test func savedLookupsAloneDontBlockAnImport() async throws {
        let world = try await World()
        let data = try await world.backup.export()
        let target = try AppDatabase.inMemory()
        try await GRDBLookupCacheRepository(database: target)
            .put(CachedLookup(barcode: LookupCacheStoreTests.jugCode, outcome: .notFound, fetchedAt: t0))
        try await GRDBBackup(database: target).import(data)
    }
}

// MARK: - Adding to a lot, and walk Undo

@Suite struct AddToLotTests {
    @Test func addIncreasesTheQuantityAndKeepsTheAcquiredDate() async throws {
        let world = try await World()
        let lot = world.lot(quantity: 6)
        try await world.lots.save(lot)
        let after = try await world.lots.add(lot.id, amount: 2)
        #expect(isApproximately(after.quantity, 8))
        #expect(after.acquiredDate == lot.acquiredDate)
        #expect(try await world.stored(lot.id) == after)
    }

    @Test func addRefusesArchivedMissingAndInvalid() async throws {
        let world = try await World()
        let lot = world.lot(quantity: 1)
        try await world.lots.save(lot)
        try await world.lots.archive(lot.id)
        await #expect(throws: RepositoryError.lotArchived(lot.id)) { try await world.lots.add(lot.id, amount: 1) }
        let missing = LotID()
        await #expect(throws: RepositoryError.lotNotFound(missing)) { try await world.lots.add(missing, amount: 1) }
        let live = world.lot()
        try await world.lots.save(live)
        for amount in [0.0, -1, .nan, .infinity] {
            await #expect(throws: RepositoryError.self) { try await world.lots.add(live.id, amount: amount) }
        }
        #expect(try await world.stored(live.id)?.quantity == 10)
    }

    @Test func concurrentAddsBothLand() async throws {
        let world = try await World()
        let lot = world.lot(quantity: 0.5)
        try await world.lots.save(lot)
        async let first = world.lots.add(lot.id, amount: 1)
        async let second = world.lots.add(lot.id, amount: 2)
        _ = try await (first, second)
        #expect(try await world.stored(lot.id).map { isApproximately($0.quantity, 3.5) } == true)
    }

    @Test func deleteIfUnusedOnlyDeletesAProductWithNoLots() async throws {
        let world = try await World()
        try await world.lots.save(world.lot())
        #expect(try await !world.products.deleteIfUnused(world.rice.id))
        #expect(try await world.products.get(world.rice.id) != nil)

        let beans = Product(
            name: "Beans", category: .food, role: .supply, unitKind: .count, shelfLifeProfileKey: "canned_low_acid")
        try await world.products.save(beans)
        try await GRDBShelfLifeOverrideRepository(database: world.db).save(ShelfLifeOverride(extensionMonths: 1), for: beans.id)
        #expect(try await world.products.deleteIfUnused(beans.id))
        #expect(try await world.products.get(beans.id) == nil)
        #expect(try await GRDBShelfLifeOverrideRepository(database: world.db).override(for: beans.id) == nil)
        #expect(try await !world.products.deleteIfUnused(beans.id))
    }

    /// Decision 15: undoing a walk Add that created the product and its lot leaves neither behind.
    @Test func undoingACreatedProductAndLotLeavesNothing() async throws {
        let world = try await World()
        let beans = Product(
            name: "Beans", barcode: "4006381333931", category: .food, role: .supply, unitKind: .count,
            shelfLifeProfileKey: "canned_low_acid")
        let lot = Lot(productID: beans.id, quantity: 6, acquiredDate: day("2026-10-18"), locationID: world.pantry.id)
        try await world.lots.save(lot, newProduct: beans)

        try await world.lots.delete(lot.id)
        #expect(try await world.products.deleteIfUnused(beans.id))
        #expect(try await world.stored(lot.id) == nil)
        #expect(try await world.products.find(barcode: "4006381333931") == nil)
    }

    @Test func undoingAnAddRestoresTheEarlierQuantity() async throws {
        let world = try await World()
        let lot = world.lot(quantity: 6)
        try await world.lots.save(lot)
        try await world.lots.add(lot.id, amount: 1)
        try await world.lots.consume(lot.id, amount: 1)
        let back = try #require(try await world.stored(lot.id))
        #expect(isApproximately(back.quantity, 6))
        #expect(!back.archived)
    }
}
