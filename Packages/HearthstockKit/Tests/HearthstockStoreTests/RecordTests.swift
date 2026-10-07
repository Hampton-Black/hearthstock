import Foundation
import GRDB
import HearthstockCore
import enum HearthstockCore.Category
import Synchronization
import Testing
@testable import HearthstockStore

/// A clock the test advances by hand.
private final class TestClock: Sendable {
    private let current: Mutex<Date>

    init(_ start: Date) { current = Mutex(start) }

    var clock: StoreClock { StoreClock { [self] in current.withLock { $0 } } }

    func set(_ date: Date) { current.withLock { $0 = date } }
}

private func date(_ year: Int, _ month: Int, _ day: Int) -> CalendarDate {
    CalendarDate(year: year, month: month, day: day)!
}

/// Month, leap-day and year edges, plus the extremes of the supported range.
private let boundaryDates: [CalendarDate] = [
    date(1, 1, 1), date(1999, 12, 31), date(2000, 1, 1), date(2000, 2, 29), date(2023, 2, 28),
    date(2024, 2, 29), date(2024, 3, 1), date(2026, 1, 31), date(2026, 12, 31), date(9999, 12, 31),
]

private let t0 = Date(timeIntervalSince1970: 1_767_225_600.125)  // 2026-01-01T00:00:00.125Z
private let t1 = Date(timeIntervalSince1970: 1_769_904_000.5)  // 2026-02-01T00:00:00.500Z

/// Core → record → database → record → Core, for every entity.
@Suite struct RecordRoundTripTests {
    private let site = Site(name: "Main house")
    private let product = Product(
        name: "Rice", category: .food, role: .supply, unitKind: .mass, shelfLifeProfileKey: "dry-grain")

    private func location(in site: Site) -> Location {
        Location(siteID: site.id, name: "Pantry")
    }

    /// A database holding `site`, `product` and one location, ready for lots and kits.
    private func seeded(_ location: Location) throws -> AppDatabase {
        let db = try AppDatabase.inMemory()
        try db.writer.write { db in
            try SiteRecord(site).insert(db, clock: .system)
            try ProductRecord(product).insert(db, clock: .system)
            try LocationRecord(location).insert(db, clock: .system)
        }
        return db
    }

    private func roundTrip<R: StoredRecord>(_ record: R, in db: AppDatabase, key: String) throws -> R {
        try db.writer.write { db in
            try record.insert(db, clock: .system)
            return try #require(try R.fetchOne(db, key: key))
        }
    }

    // MARK: Site and person

    @Test func siteRoundTrips() throws {
        let db = try AppDatabase.inMemory()
        let original = Site(name: "Bug-out cabin ⛺️")
        let back = try db.writer.write { db in
            try SiteRecord(original).insert(db, clock: .system)
            return try #require(try SiteRecord.fetchOne(db, key: original.id.stored)).toCore()
        }
        #expect(back == original)
    }

    @Test(arguments: [
        Person(siteID: SiteID(), name: "Adult"),
        Person(siteID: SiteID(), name: "Toddler", kcalPerDay: 0, waterGalPerDay: 0),
        Person(siteID: SiteID(), name: "Athlete", kcalPerDay: 3500.5, waterGalPerDay: 1.75),
    ])
    func personRoundTrips(template: Person) throws {
        let db = try AppDatabase.inMemory()
        let site = Site(name: "Main house")
        var original = template
        original.siteID = site.id
        let back = try db.writer.write { db in
            try SiteRecord(site).insert(db, clock: .system)
            try PersonRecord(original).insert(db, clock: .system)
            return try #require(try PersonRecord.fetchOne(db, key: original.id.stored)).toCore()
        }
        #expect(back == original)
    }

    // MARK: Shelf-life overrides

    @Test(arguments: [
        ShelfLifeOverride(),
        ShelfLifeOverride(extensionMonths: 6),
        ShelfLifeOverride(extensionMonths: 0, packagedLifeMonths: 0, rotationMonths: 0),
        ShelfLifeOverride(
            dateType: ShelfLifeDateType.none, extensionMonths: 1, packagedLifeMonths: 120, rotationMonths: 18),
    ] + ShelfLifeDateType.allCases.map { ShelfLifeOverride(dateType: $0) })
    func productOverrideRoundTrips(original: ShelfLifeOverride) throws {
        let db = try seeded(location(in: site))
        let record = ShelfLifeOverrideRecord(original, productID: product.id)
        let back = try roundTrip(record, in: db, key: record.id)
        #expect(back.productId == product.id.stored)
        #expect(back.lotId == nil)
        #expect(try back.toCore() == original)
    }

    @Test func lotOverrideRoundTrips() throws {
        let place = location(in: site)
        let db = try seeded(place)
        let lot = Lot(productID: product.id, quantity: 1, acquiredDate: date(2026, 1, 1), locationID: place.id)
        try db.writer.write { try LotRecord(lot, siteID: site.id).insert($0, clock: .system) }
        let original = ShelfLifeOverride(dateType: .useBy, extensionMonths: 2)
        let record = ShelfLifeOverrideRecord(original, lotID: lot.id)
        let back = try roundTrip(record, in: db, key: record.id)
        #expect(back.lotId == lot.id.stored)
        #expect(back.productId == nil)
        #expect(try back.toCore() == original)
    }

    // MARK: Location and kit

    @Test(arguments: [nil] + ClimateClass.allCases.map(Optional.some))
    func locationRoundTripsEveryClimateClass(climate: ClimateClass?) throws {
        let original = Location(siteID: site.id, name: "Garage", climateClass: climate)
        let db = try seeded(self.location(in: site))
        let back = try roundTrip(LocationRecord(original), in: db, key: original.id.stored).toCore()
        #expect(back == original)
    }

    @Test(arguments: [nil] + Humidity.allCases.map(Optional.some))
    func locationRoundTripsEveryHumidity(humidity: Humidity?) throws {
        let original = Location(siteID: site.id, name: "Cellar", humidity: humidity)
        let db = try seeded(self.location(in: site))
        let back = try roundTrip(LocationRecord(original), in: db, key: original.id.stored).toCore()
        #expect(back == original)
    }

    @Test(arguments: [nil, 0.33, 0.5, 1.0, 1.25, 2.0])
    func locationRoundTripsItsMultiplierOverride(multiplier: Double?) throws {
        let original = Location(siteID: site.id, name: "Shed", climateClass: .hot, climateMultiplierOverride: multiplier)
        let db = try seeded(self.location(in: site))
        let back = try roundTrip(LocationRecord(original), in: db, key: original.id.stored).toCore()
        #expect(back == original)
    }

    @Test func locationWithParentRoundTrips() throws {
        let parent = location(in: site)
        let original = Location(
            siteID: site.id, name: "Top shelf", parentID: parent.id, climateClass: .coolDry, humidity: .dry)
        let db = try seeded(parent)
        let back = try roundTrip(LocationRecord(original), in: db, key: original.id.stored).toCore()
        #expect(back == original)
    }

    @Test(arguments: [nil, date(2026, 1, 31)] + boundaryDates.map(Optional.some))
    func kitRoundTripsWithTemplateAndInspectionDate(inspected: CalendarDate?) throws {
        let bag = Location(siteID: site.id, name: "Go-bag")
        let original = Kit(
            locationID: bag.id, templateID: KitTemplateID(), countsTowardSiteRunway: true,
            lastInspectedDate: inspected)
        let db = try seeded(location(in: site))
        let back = try db.writer.write { db in
            // The location names the kit and the kit names the location; the kit foreign key is
            // deferred, so both rows go in one transaction.
            var withKit = bag
            withKit.kitID = original.id
            try LocationRecord(withKit).insert(db, clock: .system)
            try KitRecord(original, homeSiteID: site.id).insert(db, clock: .system)
            return try #require(try KitRecord.fetchOne(db, key: original.id.stored)).toCore()
        }
        #expect(back == original)
    }

    @Test func kitRoundTripsWithNilOptionalsAndDefaults() throws {
        let bag = Location(siteID: site.id, name: "Car kit")
        let original = Kit(locationID: bag.id)
        let db = try seeded(location(in: site))
        let (kit, location) = try db.writer.write { db in
            var withKit = bag
            withKit.kitID = original.id
            try LocationRecord(withKit).insert(db, clock: .system)
            try KitRecord(original, homeSiteID: site.id).insert(db, clock: .system)
            return (
                try #require(try KitRecord.fetchOne(db, key: original.id.stored)).toCore(),
                try #require(try LocationRecord.fetchOne(db, key: bag.id.stored)).toCore()
            )
        }
        #expect(kit == original)
        #expect(!kit.countsTowardSiteRunway)
        #expect(location.kitID == original.id)
    }

    // MARK: Product

    @Test(arguments: Category.allCases)
    func productRoundTripsEveryCategory(category: Category) throws {
        let original = Product(
            name: "Item", category: category, role: .supply, unitKind: .count, shelfLifeProfileKey: "k")
        let db = try seeded(location(in: site))
        #expect(try roundTrip(ProductRecord(original), in: db, key: original.id.stored).toCore() == original)
    }

    @Test(arguments: ProductRole.allCases)
    func productRoundTripsEveryRole(role: ProductRole) throws {
        let original = Product(
            name: "Item", category: .tools, role: role, unitKind: .count, shelfLifeProfileKey: "k")
        let db = try seeded(location(in: site))
        #expect(try roundTrip(ProductRecord(original), in: db, key: original.id.stored).toCore() == original)
    }

    @Test(arguments: UnitKind.allCases)
    func productRoundTripsEveryUnitKind(unitKind: UnitKind) throws {
        let original = Product(
            name: "Item", category: .other, role: .supply, unitKind: unitKind, shelfLifeProfileKey: "k")
        let db = try seeded(location(in: site))
        let back = try roundTrip(ProductRecord(original), in: db, key: original.id.stored).toCore()
        #expect(back == original)
        #expect(back.baseUnit == unitKind.baseUnit)
    }

    @Test func productRoundTripsWithEveryOptionalSet() throws {
        let original = Product(
            name: "Peanut butter", barcode: "012345678905", category: .food, role: .supply,
            unitKind: .mass, kcalPerBaseUnit: 2_665.5, potableWaterGalPerBaseUnit: 0,
            shelfLifeProfileKey: "peanut-butter")
        let db = try seeded(location(in: site))
        #expect(try roundTrip(ProductRecord(original), in: db, key: original.id.stored).toCore() == original)
    }

    // MARK: Lot

    private func lotFixture(_ lot: Lot) throws -> Lot {
        let home = Location(id: lot.locationID, siteID: site.id, name: "Shelf")
        let db = try seeded(location(in: site))
        var lot = lot
        lot.productID = product.id
        return try db.writer.write { db in
            try LocationRecord(home).insert(db, clock: .system)
            try LotRecord(lot, siteID: site.id).insert(db, clock: .system)
            return try #require(try LotRecord.fetchOne(db, key: lot.id.stored)).toCore()
        }
    }

    private func lot(
        acquired: CalendarDate = date(2026, 1, 1),
        printed: CalendarDate? = nil,
        packaging: Packaging = .none,
        climateOverride: ClimateClass? = nil,
        notes: String? = nil,
        opened: Bool = false,
        archived: Bool = false,
        quantity: Double = 20
    ) -> Lot {
        Lot(
            productID: product.id, quantity: quantity, acquiredDate: acquired, printedDate: printed,
            packaging: packaging, locationID: LocationID(), climateOverride: climateOverride,
            notes: notes, opened: opened, archived: archived)
    }

    @Test func lotRoundTripsWithNilOptionalsAndDefaults() throws {
        let original = lot()
        var expected = original
        expected.productID = product.id
        #expect(try lotFixture(original) == expected)
        #expect(original.printedDate == nil && original.climateOverride == nil && original.notes == nil)
    }

    @Test(arguments: Packaging.allCases)
    func lotRoundTripsEveryPackaging(packaging: Packaging) throws {
        let original = lot(packaging: packaging)
        #expect(try lotFixture(original) == original)
    }

    @Test(arguments: ClimateClass.allCases)
    func lotRoundTripsEveryClimateOverride(climate: ClimateClass) throws {
        let original = lot(climateOverride: climate)
        #expect(try lotFixture(original) == original)
    }

    @Test(arguments: boundaryDates)
    func lotRoundTripsBoundaryDates(day: CalendarDate) throws {
        let original = lot(acquired: day, printed: day)
        #expect(try lotFixture(original) == original)
    }

    @Test(arguments: [(true, true), (true, false), (false, true), (false, false)])
    func lotRoundTripsFlagCombinations(opened: Bool, archived: Bool) throws {
        let original = lot(opened: opened, archived: archived)
        #expect(try lotFixture(original) == original)
    }

    @Test(arguments: [0, 0.25, 19.999, 1_000_000])
    func lotRoundTripsQuantities(quantity: Double) throws {
        let original = lot(quantity: quantity)
        #expect(try lotFixture(original) == original)
    }

    @Test func lotRoundTripsNotes() throws {
        let original = lot(notes: "Bought at Costco, \"bulk\" – 2 × 10 lb\nsecond line")
        #expect(try lotFixture(original) == original)
    }
}

/// `createdAt` and `updatedAt`, and the injectable clock behind them.
@Suite struct RecordTimestampTests {
    private let site = Site(name: "Main house")

    private func database() throws -> AppDatabase {
        try AppDatabase.inMemory()
    }

    private func timestamps(_ db: AppDatabase) throws -> (created: String, updated: String) {
        try db.writer.read { db in
            let row = try #require(try Row.fetchOne(db, sql: "SELECT createdAt, updatedAt FROM site"))
            return (row["createdAt"], row["updatedAt"])
        }
    }

    @Test func insertStampsBothTimestampsFromTheClock() throws {
        let db = try database()
        try db.writer.write { try SiteRecord(site).insert($0, clock: .fixed(t0)) }
        let stored = try timestamps(db)
        #expect(stored.created == "2026-01-01T00:00:00.125Z")
        #expect(stored.updated == "2026-01-01T00:00:00.125Z")
    }

    @Test func updateMovesUpdatedAtAndLeavesCreatedAtAlone() throws {
        let db = try database()
        let clock = TestClock(t0)
        try db.writer.write { try SiteRecord(site).insert($0, clock: clock.clock) }

        clock.set(t1)
        var renamed = site
        renamed.name = "Renamed"
        try db.writer.write { try SiteRecord(renamed).update($0, clock: clock.clock) }

        let stored = try timestamps(db)
        #expect(stored.created == "2026-01-01T00:00:00.125Z")
        #expect(stored.updated == "2026-02-01T00:00:00.500Z")
        let name = try db.writer.read { try String.fetchOne($0, sql: "SELECT name FROM site") }
        #expect(name == "Renamed")
    }

    @Test func updateIgnoresACreatedAtHeldInMemory() throws {
        let db = try database()
        try db.writer.write { try SiteRecord(site).insert($0, clock: .fixed(t0)) }
        var record = SiteRecord(site)
        record.createdAt = t1  // wrong on purpose
        try db.writer.write { try record.update($0, clock: .fixed(t1)) }
        #expect(try timestamps(db).created == "2026-01-01T00:00:00.125Z")
    }

    @Test func saveInsertsThenUpdates() throws {
        let db = try database()
        let clock = TestClock(t0)
        try db.writer.write { try SiteRecord(site).save($0, clock: clock.clock) }
        #expect(try timestamps(db) == ("2026-01-01T00:00:00.125Z", "2026-01-01T00:00:00.125Z"))

        clock.set(t1)
        try db.writer.write { try SiteRecord(site).save($0, clock: clock.clock) }
        #expect(try timestamps(db) == ("2026-01-01T00:00:00.125Z", "2026-02-01T00:00:00.500Z"))
        #expect(try db.writer.read { try SiteRecord.fetchCount($0) } == 1)
    }

    @Test func updateOfAMissingRowThrows() throws {
        let db = try database()
        #expect(throws: (any Error).self) {
            try db.writer.write { try SiteRecord(site).update($0, clock: .fixed(t0)) }
        }
    }

    @Test func fetchedRecordsCarryTheStoredTimestamps() throws {
        let db = try database()
        try db.writer.write { try SiteRecord(site).insert($0, clock: .fixed(t0)) }
        let fetched = try db.writer.read { try #require(try SiteRecord.fetchOne($0, key: site.id.stored)) }
        #expect(fetched.createdAt == t0)
        #expect(fetched.updatedAt == t0)
    }

    @Test func timestampsUseTheSameFormatAsTheSchemaDefaults() throws {
        let db = try database()
        try db.writer.write { db in
            try db.execute(sql: "INSERT INTO site (id, name) VALUES ('raw', 'Raw')")
            try SiteRecord(site).insert(db, clock: .fixed(t0))
        }
        let all = try db.writer.read { try String.fetchAll($0, sql: "SELECT createdAt FROM site") }
        #expect(all.count == 2)
        for value in all {
            #expect(value.wholeMatch(of: /\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z/) != nil, "\(value)")
        }
        // A row written by the schema default decodes through the record too.
        let raw = try db.writer.read { try #require(try SiteRecord.fetchOne($0, key: "raw")) }
        #expect(raw.createdAt != nil && raw.updatedAt != nil)
    }

    @Test func updateCanClearAnOptionalColumn() throws {
        let db = try database()
        let parent = Location(siteID: site.id, name: "Garage", climateClass: .hot, humidity: .dry)
        try db.writer.write { db in
            try SiteRecord(site).insert(db, clock: .fixed(t0))
            try LocationRecord(parent).insert(db, clock: .fixed(t0))
        }
        var cleared = parent
        cleared.climateClass = nil
        cleared.humidity = nil
        try db.writer.write { try LocationRecord(cleared).update($0, clock: .fixed(t1)) }
        let back = try db.writer.read { try #require(try LocationRecord.fetchOne($0, key: parent.id.stored)) }
        #expect(try back.toCore() == cleared)
    }

    @Test func updateWritesAndClearsTheClimateMultiplierOverride() throws {
        let db = try database()
        let location = Location(siteID: site.id, name: "Garage", climateMultiplierOverride: 0.6)
        try db.writer.write { db in
            try SiteRecord(site).insert(db, clock: .fixed(t0))
            try LocationRecord(location).insert(db, clock: .fixed(t0))
        }
        func stored() throws -> Double? {
            try db.writer.read { try Double.fetchOne($0, sql: "SELECT climateMultiplierOverride FROM location") }
        }
        #expect(try stored() == 0.6)

        var changed = location
        changed.climateMultiplierOverride = 0.75
        try db.writer.write { try LocationRecord(changed).update($0, clock: .fixed(t1)) }
        #expect(try stored() == 0.75)

        changed.climateMultiplierOverride = nil
        try db.writer.write { try LocationRecord(changed).update($0, clock: .fixed(t1)) }
        #expect(try stored() == nil)
    }

    @Test func timestampsRoundToTheNearestMillisecond() {
        let awkward = Date(timeIntervalSince1970: 1_767_225_600.123)  // not exactly representable
        #expect(StoredTimestamp.string(from: awkward) == "2026-01-01T00:00:00.123Z")
        let parsed = StoredTimestamp.date(from: "2026-01-01T00:00:00.123Z")
        #expect(parsed.map { abs($0.timeIntervalSince(awkward)) < 0.0005 } == true)
    }

    @Test func timestampsBeforeTheEpochFormatCorrectly() {
        let date = Date(timeIntervalSince1970: -0.5)
        #expect(StoredTimestamp.string(from: date) == "1969-12-31T23:59:59.500Z")
        #expect(StoredTimestamp.date(from: "1969-12-31T23:59:59.500Z") == date)
    }

    @Test func systemClockReadsTheWallClock() {
        let before = Date()
        let now = StoreClock.system.now()
        #expect(now >= before && now <= Date())
    }
}

/// Stored values that don't map back to Core.
@Suite struct RecordMappingErrorTests {
    @Test func unknownEnumValueThrows() throws {
        var record = ProductRecord(
            Product(name: "x", category: .food, role: .supply, unitKind: .mass, shelfLifeProfileKey: "k"))
        record.category = "bogus"
        #expect(throws: RecordMappingError(table: "product", column: "category", value: "bogus")) {
            try record.toCore()
        }
    }

    @Test func malformedIDThrows() throws {
        var record = SiteRecord(Site(name: "x"))
        record.id = "not-a-uuid"
        #expect(throws: RecordMappingError(table: "site", column: "id", value: "not-a-uuid")) {
            try record.toCore()
        }
    }

    @Test func malformedDateThrows() throws {
        var record = LotRecord(
            Lot(productID: ProductID(), quantity: 1, acquiredDate: date(2026, 1, 1), locationID: LocationID()),
            siteID: SiteID())
        record.acquiredDate = "2026-02-30"
        #expect(throws: RecordMappingError(table: "lot", column: "acquiredDate", value: "2026-02-30")) {
            try record.toCore()
        }
    }

    @Test func unknownOverrideDateTypeThrows() throws {
        var record = ShelfLifeOverrideRecord(ShelfLifeOverride(), productID: ProductID())
        record.dateType = "sellBy"
        #expect(throws: RecordMappingError(table: "shelf_life_override", column: "dateType", value: "sellBy")) {
            try record.toCore()
        }
    }

    @Test func storedIDsAreUppercaseUUIDStrings() {
        let id = SiteID(rawValue: UUID(uuidString: "6ba7b810-9dad-11d1-80b4-00c04fd430c8")!)
        #expect(SiteRecord(Site(id: id, name: "x")).id == "6BA7B810-9DAD-11D1-80B4-00C04FD430C8")
    }
}
