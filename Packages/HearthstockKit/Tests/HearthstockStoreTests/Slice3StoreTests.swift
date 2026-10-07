import Foundation
import GRDB
import HearthstockCore
import Synchronization
import Testing
@testable import HearthstockStore

private let t0 = Date(timeIntervalSince1970: 1_767_225_600)

/// A clock that advances a second per call, so rows get distinct, ordered timestamps.
private func tickingClock() -> StoreClock {
    let ticks = Mutex(0)
    return StoreClock { t0.addingTimeInterval(Double(ticks.withLock { $0 += 1; return $0 })) }
}

private func day(_ iso: String) -> CalendarDate { CalendarDate(iso: iso)! }

private func json(_ data: Data) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
}

private func withoutExportedAt(_ data: Data) throws -> NSDictionary {
    var object = try json(data)
    object["exportedAt"] = nil
    return object as NSDictionary
}

private func populatedDatabase(clock: StoreClock = tickingClock()) async throws -> (AppDatabase, PantryFixture) {
    let fixture = try PantryFixture.load()
    let db = try AppDatabase.inMemory()
    try await fixture.populate(db, clock: clock)
    try await GRDBShelfLifeOverrideRepository(database: db, clock: clock)
        .save(ShelfLifeOverride(extensionMonths: 6), for: fixture.lots[1].id)
    return (db, fixture)
}

// MARK: - Notice window

@Suite struct NoticeWindowStoreTests {
    @Test func noticeWindowRoundTripsThroughTheSiteRepository() async throws {
        let db = try AppDatabase.inMemory()
        let sites = GRDBSiteRepository(database: db)
        var site = try await sites.ensureDefaultSite()
        #expect(site.noticeWindowDays == 30)
        site.noticeWindowDays = 14
        site.name = "Main house"
        try await sites.save(site)
        #expect(try await sites.get(site.id) == site)
        #expect(try await GRDBRunwayInputsLoader(database: db).load(siteID: site.id).site.noticeWindowDays == 14)
    }

    @Test(arguments: [0, -3])
    func aNonPositiveWindowIsRefused(days: Int) async throws {
        let db = try AppDatabase.inMemory()
        let sites = GRDBSiteRepository(database: db)
        var site = try await sites.ensureDefaultSite()
        site.noticeWindowDays = days
        await #expect(throws: RepositoryError.invalidNoticeWindow(days)) { try await sites.save(site) }
        #expect(try await sites.get(site.id)?.noticeWindowDays == 30)
        // The schema refuses it too, however it arrives.
        #expect(throws: DatabaseError.self) {
            try db.writer.write { try $0.execute(sql: "UPDATE site SET noticeWindowDays = 0") }
        }
    }

    @Test func rowsFromBeforeTheMigrationGetThirtyDays() async throws {
        let db = try AppDatabase.inMemory()
        try await db.writer.write { try $0.execute(sql: "INSERT INTO site (id, name) VALUES (?, 'Old')", arguments: [SiteID().stored]) }
        #expect(try await GRDBSiteRepository(database: db).list().map(\.noticeWindowDays) == [30])
    }

    @Test func noticeWindowRoundTripsThroughABackup() async throws {
        let (source, fixture) = try await populatedDatabase()
        var site = fixture.site
        site.noticeWindowDays = 45
        try await GRDBSiteRepository(database: source).save(site)
        let data = try await GRDBBackup(database: source).export()
        let sites = try #require(try json(data)["sites"] as? [[String: Any]])
        #expect(sites.first?["noticeWindowDays"] as? Int == 45)

        let target = try AppDatabase.inMemory()
        try await GRDBBackup(database: target).import(data)
        #expect(try await GRDBSiteRepository(database: target).get(site.id)?.noticeWindowDays == 45)
    }

    @Test func aVersionOneBackupImportsWithThirtyDays() async throws {
        let (source, fixture) = try await populatedDatabase()
        var document = try json(await GRDBBackup(database: source).export())
        document["formatVersion"] = 1
        document["sites"] = try #require(document["sites"] as? [[String: Any]]).map { site in
            var old = site
            old["noticeWindowDays"] = nil
            return old
        }
        let data = try JSONSerialization.data(withJSONObject: document)

        let target = try AppDatabase.inMemory()
        try await GRDBBackup(database: target).import(data)
        #expect(try await GRDBSiteRepository(database: target).get(fixture.site.id)?.noticeWindowDays == 30)
        let restored = try AppDatabase.inMemory()
        try await GRDBBackup(database: restored).restore(data)
        #expect(try await GRDBSiteRepository(database: restored).get(fixture.site.id)?.noticeWindowDays == 30)
    }
}

// MARK: - Deletes

@Suite struct DeleteStoreTests {
    @Test func deletingALotRemovesItAndItsOverride() async throws {
        let (db, fixture) = try await populatedDatabase()
        let lot = fixture.lots[1]
        let overrides = GRDBShelfLifeOverrideRepository(database: db)
        #expect(try await overrides.override(for: lot.id) != nil)

        let lots = GRDBLotRepository(database: db)
        try await lots.delete(lot.id)
        let remaining = try await lots.list(siteID: fixture.site.id, includeArchived: true)
        #expect(!remaining.contains { $0.id == lot.id })
        #expect(remaining.count == fixture.lots.count - 1)
        #expect(try await overrides.override(for: lot.id) == nil)
        let rows = try await db.writer.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM shelf_life_override") }
        #expect(rows == 0)

        try await lots.delete(lot.id)  // already gone: nothing happens
        try await lots.delete(LotID())
    }

    @Test func deletingAKitLetsItsLocationBeDeleted() async throws {
        let db = try AppDatabase.inMemory()
        let site = try await GRDBSiteRepository(database: db).ensureDefaultSite()
        let locations = GRDBLocationRepository(database: db)
        let kits = GRDBKitRepository(database: db)
        let bag = Location(siteID: site.id, name: "Go-bag")
        try await locations.save(bag)
        let kit = Kit(locationID: bag.id)
        try await kits.save(kit)
        await #expect(throws: RepositoryError.locationHasKit(bag.id)) { try await locations.delete(bag.id) }

        try await kits.delete(kit.id)
        #expect(try await kits.list(siteID: site.id).isEmpty)
        #expect(try await locations.list(siteID: site.id).first?.kitID == nil)
        try await locations.delete(bag.id)
        #expect(try await locations.list(siteID: site.id).isEmpty)

        try await kits.delete(kit.id)  // already gone: nothing happens
    }
}

// MARK: - Products

@Suite struct ProductStoreSlice3Tests {
    struct Setup {
        let db: AppDatabase
        let site: Site
        let pantry: Location
        let products: GRDBProductRepository
        let lots: GRDBLotRepository

        init() async throws {
            db = try AppDatabase.inMemory()
            let clock = tickingClock()
            site = try await GRDBSiteRepository(database: db, clock: clock).ensureDefaultSite()
            pantry = Location(siteID: site.id, name: "Pantry")
            try await GRDBLocationRepository(database: db, clock: clock).save(pantry)
            products = GRDBProductRepository(database: db, clock: clock)
            lots = GRDBLotRepository(database: db, clock: clock)
        }

        func product(_ name: String, unitKind: UnitKind = .mass) -> Product {
            Product(
                name: name, category: .food, role: .supply, unitKind: unitKind, kcalPerBaseUnit: 1600,
                shelfLifeProfileKey: "white_rice")
        }

        func lot(of product: Product, at location: Location? = nil, quantity: Double = 10) -> Lot {
            Lot(productID: product.id, quantity: quantity, acquiredDate: day("2026-01-01"),
                locationID: (location ?? pantry).id)
        }

        func productCount() async throws -> Int {
            try await db.writer.read { try ProductRecord.fetchCount($0) }
        }
    }

    @Test func newProductAndItsLotAreWrittenTogether() async throws {
        let setup = try await Setup()
        let rice = setup.product("Rice")
        let lot = setup.lot(of: rice)
        try await setup.lots.save(lot, newProduct: rice)
        #expect(try await setup.products.get(rice.id) == rice)
        #expect(try await setup.lots.list(siteID: setup.site.id, includeArchived: false) == [lot])
    }

    @Test func aLotThatFailsLeavesNoProductBehind() async throws {
        let setup = try await Setup()
        let rice = setup.product("Rice")
        let nowhere = Location(siteID: setup.site.id, name: "Not saved")
        await #expect(throws: RepositoryError.locationNotFound(nowhere.id)) {
            try await setup.lots.save(setup.lot(of: rice, at: nowhere), newProduct: rice)
        }
        #expect(try await setup.productCount() == 0)

        // A lot the schema refuses (negative quantity) rolls the product back too.
        await #expect(throws: DatabaseError.self) {
            try await setup.lots.save(setup.lot(of: rice, quantity: -1), newProduct: rice)
        }
        #expect(try await setup.productCount() == 0)
    }

    @Test func aLotOfAnotherProductIsRefused() async throws {
        let setup = try await Setup()
        let rice = setup.product("Rice")
        let beans = setup.product("Beans")
        let lot = setup.lot(of: beans)
        await #expect(throws: RepositoryError.lotProductMismatch(lot.id, rice.id)) {
            try await setup.lots.save(lot, newProduct: rice)
        }
        #expect(try await setup.productCount() == 0)
    }

    @Test func anExistingProductIsNotANewProduct() async throws {
        let setup = try await Setup()
        let rice = setup.product("Rice")
        try await setup.products.save(rice)
        await #expect(throws: DatabaseError.self) {
            try await setup.lots.save(setup.lot(of: rice), newProduct: rice)
        }
        #expect(try await setup.lots.list(siteID: setup.site.id, includeArchived: true).isEmpty)
    }

    @Test func recentlyUsedProductsComeFirst() async throws {
        let setup = try await Setup()
        let oats = setup.product("Oats"), beans = setup.product("Beans"), rice = setup.product("Rice")
        try await setup.products.save(oats)
        try await setup.products.save(beans)
        try await setup.products.save(rice)
        #expect(try await setup.products.listByRecentUse().map(\.name) == ["Rice", "Beans", "Oats"])

        try await setup.lots.save(setup.lot(of: oats))  // a new lot of oats makes it the most recent
        #expect(try await setup.products.listByRecentUse().map(\.name) == ["Oats", "Rice", "Beans"])

        var renamed = beans
        renamed.name = "Black beans"
        try await setup.products.save(renamed)  // an edit counts as use
        #expect(try await setup.products.listByRecentUse().map(\.name) == ["Black beans", "Oats", "Rice"])
    }

    @Test func unitKindIsLockedOnceTheProductHasLots() async throws {
        let setup = try await Setup()
        var rice = setup.product("Rice")
        try await setup.products.save(rice)
        #expect(try await setup.products.hasLots(rice.id) == false)

        rice.unitKind = .count  // no lots yet: free to change
        try await setup.products.save(rice)
        try await setup.lots.save(setup.lot(of: rice))
        #expect(try await setup.products.hasLots(rice.id))

        var changed = rice
        changed.unitKind = .mass
        await #expect(throws: RepositoryError.unitKindLocked(rice.id)) { try await setup.products.save(changed) }
        #expect(try await setup.products.get(rice.id)?.unitKind == .count)

        var renamed = rice
        renamed.name = "Rice, 1 lb bag"  // other edits are fine
        try await setup.products.save(renamed)
    }

    @Test func archivedLotsStillLockTheUnitKind() async throws {
        let setup = try await Setup()
        let rice = setup.product("Rice")
        let lot = setup.lot(of: rice, quantity: 1)
        try await setup.lots.save(lot, newProduct: rice)
        try await setup.lots.consume(lot.id, amount: 1)
        #expect(try await setup.products.hasLots(rice.id))
    }
}

// MARK: - Restore and summaries

@Suite struct RestoreTests {
    @Test func restoreOverAPopulatedDatabaseLeavesExactlyTheFilesContents() async throws {
        let (source, _) = try await populatedDatabase()
        let file = try await GRDBBackup(database: source, clock: .fixed(t0)).export()

        let target = try AppDatabase.inMemory()
        let site = try await GRDBSiteRepository(database: target).ensureDefaultSite()
        let shed = Location(siteID: site.id, name: "Shed")
        try await GRDBLocationRepository(database: target).save(shed)
        let child = Location(siteID: site.id, name: "Shelf", parentID: shed.id)
        try await GRDBLocationRepository(database: target).save(child)
        try await GRDBKitRepository(database: target).save(Kit(locationID: child.id))
        try await GRDBPersonRepository(database: target).save(Person(siteID: site.id, name: "Someone"))

        try await GRDBBackup(database: target).restore(file)
        let after = try await GRDBBackup(database: target, clock: .fixed(t0)).export()
        #expect(try withoutExportedAt(after) == withoutExportedAt(file))
        #expect(try await GRDBSiteRepository(database: target).get(site.id) == nil)
    }

    @Test func aRestoreThatFailsPartwayLeavesTheOriginalData() async throws {
        let (source, fixture) = try await populatedDatabase()
        var document = try json(await GRDBBackup(database: source).export())
        var lots = try #require(document["lots"] as? [[String: Any]])
        lots[lots.count - 1]["locationId"] = LocationID().stored  // refused by the foreign key, last table written
        document["lots"] = lots
        let bad = try JSONSerialization.data(withJSONObject: document)

        let (target, _) = try await populatedDatabase()
        let before = try await GRDBBackup(database: target, clock: .fixed(t0)).export()
        do {
            try await GRDBBackup(database: target).restore(bad)
            Issue.record("restore should have failed")
        } catch let error as BackupError {
            guard case .invalidDocument = error else { throw error }
        }
        let after = try await GRDBBackup(database: target, clock: .fixed(t0)).export()
        #expect(after == before)
        #expect(try await GRDBLotRepository(database: target).list(siteID: fixture.site.id, includeArchived: true)
            .count == fixture.lots.count)
    }

    @Test(arguments: ["not json", #"{"formatVersion": 7}"#])
    func anUnreadableFileChangesNothing(text: String) async throws {
        let (target, _) = try await populatedDatabase()
        let before = try await GRDBBackup(database: target, clock: .fixed(t0)).export()
        await #expect(throws: BackupError.self) { try await GRDBBackup(database: target).restore(Data(text.utf8)) }
        await #expect(throws: BackupError.self) { try await GRDBBackup(database: target).summary(of: Data(text.utf8)) }
        #expect(try await GRDBBackup(database: target, clock: .fixed(t0)).export() == before)
    }

    @Test func exportRestoreExportMatchesApartFromExportedAt() async throws {
        let (db, _) = try await populatedDatabase()
        let first = try await GRDBBackup(database: db, clock: .fixed(t0)).export()
        try await GRDBBackup(database: db).restore(first)
        let second = try await GRDBBackup(database: db, clock: .fixed(t0.addingTimeInterval(60))).export()
        #expect(try withoutExportedAt(first) == withoutExportedAt(second))
        #expect(first != second)
    }

    @Test func summariesCountWhatAFileAndTheDatabaseHold() async throws {
        let (db, fixture) = try await populatedDatabase()
        let exportTime = Date(timeIntervalSince1970: 1_800_000_000)
        let backup = GRDBBackup(database: db, clock: .fixed(exportTime))
        let expected = BackupSummary(
            formatVersion: 2, exportedAt: exportTime, siteNames: ["Main house"], people: 2,
            locations: fixture.locations.count, products: fixture.products.count,
            lots: fixture.lots.filter { !$0.archived }.count, archivedLots: 1)
        #expect(try await backup.summary(of: backup.export()) == expected)

        var current = expected
        current.exportedAt = nil
        #expect(try await backup.currentSummary() == current)
    }

    @Test func backupErrorsReadAsSentences() {
        #expect(BackupError.unsupportedFormatVersion(9).localizedDescription.contains("format version 9"))
        #expect(BackupError.invalidDocument("missing sites").localizedDescription
            == "This file isn't a readable backup: missing sites.")
    }
}

@Suite struct IdenticalBackupTests {
    @Test func aFreshExportMatchesTheDatabase() async throws {
        let (db, _) = try await populatedDatabase()
        let backup = GRDBBackup(database: db)
        #expect(try await backup.matchesCurrentData(backup.export()))
    }

    @Test func anyChangeSinceTheExportIsADifference() async throws {
        let (db, fixture) = try await populatedDatabase()
        let backup = GRDBBackup(database: db)
        let file = try await backup.export()
        try await GRDBLotRepository(database: db).consume(fixture.lots[0].id, amount: 1)
        #expect(try await backup.matchesCurrentData(file) == false)
    }

    @Test func rowOrderInTheFileDoesNotMatter() async throws {
        let (db, _) = try await populatedDatabase()
        let backup = GRDBBackup(database: db)
        var document = try json(await backup.export())
        document["lots"] = Array(try #require(document["lots"] as? [[String: Any]]).reversed())
        #expect(try await backup.matchesCurrentData(JSONSerialization.data(withJSONObject: document)))
    }

    @Test func anUnreadableFileThrows() async throws {
        let db = try AppDatabase.inMemory()
        await #expect(throws: BackupError.self) { try await GRDBBackup(database: db).matchesCurrentData(Data("nope".utf8)) }
    }
}
