import Foundation
import GRDB
import HearthstockCore
import enum HearthstockCore.Category
import Synchronization
import Testing
@testable import HearthstockStore

private func date(_ year: Int, _ month: Int, _ day: Int) -> CalendarDate {
    CalendarDate(year: year, month: month, day: day)!
}

private let t0 = Date(timeIntervalSince1970: 1_767_225_600)

/// One in-memory database with every repository over it. The clock advances a second per call, so
/// creation order is the timestamp order.
private struct Harness {
    let db: AppDatabase
    let sites: GRDBSiteRepository
    let people: GRDBPersonRepository
    let locations: GRDBLocationRepository
    let products: GRDBProductRepository
    let lots: GRDBLotRepository
    let kits: GRDBKitRepository
    let inputs: GRDBRunwayInputsLoader

    init() throws {
        let db = try AppDatabase.inMemory()
        let ticks = Mutex(0)
        let clock = StoreClock { t0.addingTimeInterval(Double(ticks.withLock { $0 += 1; return $0 })) }
        self.db = db
        sites = GRDBSiteRepository(database: db, clock: clock)
        people = GRDBPersonRepository(database: db, clock: clock)
        locations = GRDBLocationRepository(database: db, clock: clock)
        products = GRDBProductRepository(database: db, clock: clock)
        lots = GRDBLotRepository(database: db, clock: clock)
        kits = GRDBKitRepository(database: db, clock: clock)
        inputs = GRDBRunwayInputsLoader(database: db)
    }

    static func product(_ name: String = "Rice", barcode: String? = nil) -> Product {
        Product(
            name: name, barcode: barcode, category: .food, role: .supply, unitKind: .mass,
            kcalPerBaseUnit: 1600, shelfLifeProfileKey: "white_rice")
    }

    static func lot(_ product: Product, in location: Location, quantity: Double = 10) -> Lot {
        Lot(productID: product.id, quantity: quantity, acquiredDate: date(2026, 1, 1), locationID: location.id)
    }

    /// The default site with a pantry, a rice product and one 10 lb lot of rice.
    func seed() async throws -> (site: Site, pantry: Location, rice: Product, lot: Lot) {
        let site = try await sites.ensureDefaultSite()
        let pantry = Location(siteID: site.id, name: "Pantry")
        try await locations.save(pantry)
        let rice = Self.product()
        try await products.save(rice)
        let lot = Self.lot(rice, in: pantry)
        try await lots.save(lot)
        return (site, pantry, rice, lot)
    }

    func quantity(of lot: Lot) async throws -> Double {
        try await lots.list(siteID: lotSite(lot), includeArchived: true).first { $0.id == lot.id }?.quantity ?? -1
    }

    private func lotSite(_ lot: Lot) async throws -> SiteID {
        let site = try await db.writer.read {
            try String.fetchOne($0, sql: "SELECT siteId FROM lot WHERE id = ?", arguments: [lot.id.stored])
        }
        return SiteID(rawValue: UUID(uuidString: try #require(site))!)
    }
}

@Suite struct SiteRepositoryTests {
    @Test func saveListAndGet() async throws {
        let h = try Harness()
        let first = Site(name: "Cabin")
        let second = Site(name: "Main house")
        try await h.sites.save(first)
        try await h.sites.save(second)
        #expect(try await h.sites.list() == [first, second])
        #expect(try await h.sites.get(second.id) == second)
        #expect(try await h.sites.get(SiteID()) == nil)

        var renamed = first
        renamed.name = "Bug-out cabin"
        try await h.sites.save(renamed)
        #expect(try await h.sites.list() == [renamed, second])
    }

    @Test func ensureDefaultSiteCalledTwiceCreatesOneSite() async throws {
        let h = try Harness()
        let first = try await h.sites.ensureDefaultSite()
        let second = try await h.sites.ensureDefaultSite()
        #expect(first.name == "Home")
        #expect(first == second)
        #expect(try await h.sites.list() == [first])
    }

    @Test func ensureDefaultSiteReturnsExistingSiteAndAddsNothing() async throws {
        let h = try Harness()
        let cabin = Site(name: "Cabin")
        try await h.sites.save(cabin)
        #expect(try await h.sites.ensureDefaultSite() == cabin)
        #expect(try await h.sites.list() == [cabin])
    }

    @Test func concurrentEnsureDefaultSiteCreatesOneSite() async throws {
        let h = try Harness()
        let created = try await withThrowingTaskGroup(of: Site.self) { group in
            for _ in 0..<8 { group.addTask { try await h.sites.ensureDefaultSite() } }
            return try await group.reduce(into: Set<Site>()) { $0.insert($1) }
        }
        #expect(created.count == 1)
        #expect(try await h.sites.list().count == 1)
    }
}

@Suite struct PersonRepositoryTests {
    @Test func crudIsScopedToSite() async throws {
        let h = try Harness()
        let home = try await h.sites.ensureDefaultSite()
        let cabin = Site(name: "Cabin")
        try await h.sites.save(cabin)
        let ada = Person(siteID: home.id, name: "Ada", kcalPerDay: 2200)
        let bo = Person(siteID: cabin.id, name: "Bo", waterGalPerDay: 1.5)
        try await h.people.save(ada)
        try await h.people.save(bo)
        #expect(try await h.people.list(siteID: home.id) == [ada])
        #expect(try await h.people.list(siteID: cabin.id) == [bo])

        var updated = ada
        updated.name = "Ada L."
        updated.kcalPerDay = 1800
        try await h.people.save(updated)
        #expect(try await h.people.list(siteID: home.id) == [updated])

        try await h.people.delete(ada.id)
        #expect(try await h.people.list(siteID: home.id).isEmpty)
        #expect(try await h.people.list(siteID: cabin.id) == [bo])
        try await h.people.delete(ada.id)  // already gone: not an error
    }
}

@Suite struct LocationRepositoryTests {
    @Test func crudAndNesting() async throws {
        let h = try Harness()
        let site = try await h.sites.ensureDefaultSite()
        let garage = Location(siteID: site.id, name: "Garage", climateClass: .hot, humidity: .humid)
        let shelf = Location(siteID: site.id, name: "Shelf", parentID: garage.id)
        try await h.locations.save(garage)
        try await h.locations.save(shelf)
        #expect(try await h.locations.list(siteID: site.id) == [garage, shelf])

        var moved = garage
        moved.name = "Workshop"
        moved.climateClass = nil
        try await h.locations.save(moved)
        #expect(try await h.locations.list(siteID: site.id) == [shelf, moved])

        try await h.locations.delete(shelf.id)
        #expect(try await h.locations.list(siteID: site.id) == [moved])
    }

    @Test func deletingLocationWithLotsThrowsTypedError() async throws {
        let h = try Harness()
        let seeded = try await h.seed()
        await #expect(throws: RepositoryError.locationHasLots(seeded.pantry.id)) {
            try await h.locations.delete(seeded.pantry.id)
        }
        #expect(try await h.locations.list(siteID: seeded.site.id) == [seeded.pantry])
    }

    @Test func archivedLotsStillBlockDeletion() async throws {
        let h = try Harness()
        let seeded = try await h.seed()
        try await h.lots.archive(seeded.lot.id)
        await #expect(throws: RepositoryError.locationHasLots(seeded.pantry.id)) {
            try await h.locations.delete(seeded.pantry.id)
        }
    }

    @Test func deletingLocationWithChildrenOrKitThrowsTypedError() async throws {
        let h = try Harness()
        let site = try await h.sites.ensureDefaultSite()
        let parent = Location(siteID: site.id, name: "Garage")
        let child = Location(siteID: site.id, name: "Shelf", parentID: parent.id)
        let bag = Location(siteID: site.id, name: "Go-bag")
        try await h.locations.save(parent)
        try await h.locations.save(child)
        try await h.locations.save(bag)
        try await h.kits.save(Kit(locationID: bag.id))

        await #expect(throws: RepositoryError.locationHasChildren(parent.id)) {
            try await h.locations.delete(parent.id)
        }
        await #expect(throws: RepositoryError.locationHasKit(bag.id)) {
            try await h.locations.delete(bag.id)
        }
    }
}

@Suite struct ProductRepositoryTests {
    @Test func saveGetAndUpdate() async throws {
        let h = try Harness()
        var rice = Harness.product(barcode: "0123456789012")
        try await h.products.save(rice)
        #expect(try await h.products.get(rice.id) == rice)
        #expect(try await h.products.get(ProductID()) == nil)

        rice.name = "Jasmine rice"
        rice.kcalPerBaseUnit = 1650
        try await h.products.save(rice)
        #expect(try await h.products.get(rice.id) == rice)
    }

    @Test func findByBarcode() async throws {
        let h = try Harness()
        let rice = Harness.product(barcode: "111")
        let beans = Harness.product("Beans")
        try await h.products.save(rice)
        try await h.products.save(beans)
        #expect(try await h.products.find(barcode: "111") == rice)
        #expect(try await h.products.find(barcode: "222") == nil)
    }

    @Test func searchMatchesSubstringIgnoringCaseOrderedByName() async throws {
        let h = try Harness()
        let names = ["Rice, white", "Brown RICE", "Beans", "Rolled oats"]
        for name in names { try await h.products.save(Harness.product(name)) }
        #expect(try await h.products.search(name: "rice").map(\.name) == ["Brown RICE", "Rice, white"])
        #expect(try await h.products.search(name: "zzz").isEmpty)
        #expect(try await h.products.search(name: "").map(\.name) == ["Beans", "Brown RICE", "Rice, white", "Rolled oats"])
    }

    @Test func searchTreatsWildcardsLiterally() async throws {
        let h = try Harness()
        for name in ["100% juice", "Juice", "a_b", "axb", #"back\slash"#] {
            try await h.products.save(Harness.product(name))
        }
        #expect(try await h.products.search(name: "%").map(\.name) == ["100% juice"])
        #expect(try await h.products.search(name: "a_b").map(\.name) == ["a_b"])
        #expect(try await h.products.search(name: #"\"#).map(\.name) == [#"back\slash"#])
    }
}

@Suite struct LotRepositoryTests {
    @Test func saveListAndUpdate() async throws {
        let h = try Harness()
        let seeded = try await h.seed()
        let later = Lot(
            productID: seeded.rice.id, quantity: 4, acquiredDate: date(2026, 3, 1),
            printedDate: date(2027, 1, 1), packaging: .mylarO2, locationID: seeded.pantry.id,
            climateOverride: .coolDry, notes: "Costco", opened: true)
        try await h.lots.save(later)
        #expect(try await h.lots.list(siteID: seeded.site.id, includeArchived: false) == [seeded.lot, later])

        var edited = seeded.lot
        edited.quantity = 7.5
        edited.notes = "Recounted"
        try await h.lots.save(edited)
        #expect(try await h.lots.list(siteID: seeded.site.id, includeArchived: false) == [edited, later])
    }

    @Test func siteComesFromTheLocation() async throws {
        let h = try Harness()
        let seeded = try await h.seed()
        let cabin = Site(name: "Cabin")
        try await h.sites.save(cabin)
        let loft = Location(siteID: cabin.id, name: "Loft")
        try await h.locations.save(loft)
        let cabinLot = Harness.lot(seeded.rice, in: loft, quantity: 2)
        try await h.lots.save(cabinLot)

        #expect(try await h.lots.list(siteID: seeded.site.id, includeArchived: true) == [seeded.lot])
        #expect(try await h.lots.list(siteID: cabin.id, includeArchived: true) == [cabinLot])
    }

    @Test func savingIntoMissingLocationThrowsTypedError() async throws {
        let h = try Harness()
        let seeded = try await h.seed()
        let ghost = Location(siteID: seeded.site.id, name: "Ghost")
        await #expect(throws: RepositoryError.locationNotFound(ghost.id)) {
            try await h.lots.save(Harness.lot(seeded.rice, in: ghost))
        }
    }

    @Test func archivedLotsAreListedOnlyOnRequest() async throws {
        let h = try Harness()
        let seeded = try await h.seed()
        try await h.lots.archive(seeded.lot.id)
        #expect(try await h.lots.list(siteID: seeded.site.id, includeArchived: false).isEmpty)
        let all = try await h.lots.list(siteID: seeded.site.id, includeArchived: true)
        #expect(all.map(\.id) == [seeded.lot.id])
        #expect(all.first?.archived == true)
        #expect(all.first?.quantity == 10)
    }

    @Test func archivingMissingLotThrowsTypedError() async throws {
        let h = try Harness()
        let id = LotID()
        await #expect(throws: RepositoryError.lotNotFound(id)) { try await h.lots.archive(id) }
    }

    @Test func consumeReducesQuantity() async throws {
        let h = try Harness()
        let seeded = try await h.seed()
        let after = try await h.lots.consume(seeded.lot.id, amount: 2.5)
        #expect(after.quantity == 7.5)
        #expect(after.archived == false)
        #expect(try await h.quantity(of: seeded.lot) == 7.5)
    }

    @Test func consumingToExactlyZeroArchivesTheLot() async throws {
        let h = try Harness()
        let seeded = try await h.seed()
        let after = try await h.lots.consume(seeded.lot.id, amount: 10)
        #expect(after.quantity == 0)
        #expect(after.archived)
        #expect(try await h.lots.list(siteID: seeded.site.id, includeArchived: false).isEmpty)
        #expect(try await h.lots.list(siteID: seeded.site.id, includeArchived: true) == [after])
    }

    @Test func consumingInPiecesThatSumToTheQuantityArchivesDespiteFloatingPoint() async throws {
        let h = try Harness()
        let seeded = try await h.seed()
        var lot = seeded.lot
        lot.quantity = 0.3
        try await h.lots.save(lot)
        for _ in 0..<3 { try await h.lots.consume(lot.id, amount: 0.1) }
        let all = try await h.lots.list(siteID: seeded.site.id, includeArchived: true)
        #expect(all.first?.quantity == 0)
        #expect(all.first?.archived == true)
    }

    @Test func overConsumingThrowsAndLeavesQuantityUnchanged() async throws {
        let h = try Harness()
        let seeded = try await h.seed()
        await #expect(throws: RepositoryError.insufficientQuantity(seeded.lot.id, available: 10, requested: 10.5)) {
            try await h.lots.consume(seeded.lot.id, amount: 10.5)
        }
        #expect(try await h.quantity(of: seeded.lot) == 10)
        let stored = try await h.lots.list(siteID: seeded.site.id, includeArchived: false)
        #expect(stored == [seeded.lot])
    }

    @Test(arguments: [0.0, -1.0, .nan, .infinity])
    func consumingANonPositiveOrNonFiniteAmountThrows(amount: Double) async throws {
        let h = try Harness()
        let seeded = try await h.seed()
        let error = try await #require(throws: RepositoryError.self) {
            try await h.lots.consume(seeded.lot.id, amount: amount)
        }
        guard case .invalidAmount = error else {
            Issue.record("expected invalidAmount, got \(error)")
            return
        }
        #expect(try await h.quantity(of: seeded.lot) == 10)
    }

    @Test func consumingMissingOrArchivedLotThrowsTypedError() async throws {
        let h = try Harness()
        let seeded = try await h.seed()
        let missing = LotID()
        await #expect(throws: RepositoryError.lotNotFound(missing)) {
            try await h.lots.consume(missing, amount: 1)
        }
        try await h.lots.archive(seeded.lot.id)
        await #expect(throws: RepositoryError.lotArchived(seeded.lot.id)) {
            try await h.lots.consume(seeded.lot.id, amount: 1)
        }
    }

    @Test func consumeUpdatesTimestampButNotCreation() async throws {
        let h = try Harness()
        let seeded = try await h.seed()
        func stamps() async throws -> (created: String, updated: String) {
            try await h.db.writer.read {
                let row = try #require(try Row.fetchOne(
                    $0, sql: "SELECT createdAt, updatedAt FROM lot WHERE id = ?", arguments: [seeded.lot.id.stored]))
                return (row["createdAt"], row["updatedAt"])
            }
        }
        let before = try await stamps()
        try await h.lots.consume(seeded.lot.id, amount: 1)
        let after = try await stamps()
        #expect(after.created == before.created)
        #expect(after.updated > before.updated)
    }
}

@Suite struct KitRepositoryTests {
    @Test func saveListAndUpdate() async throws {
        let h = try Harness()
        let site = try await h.sites.ensureDefaultSite()
        let cabin = Site(name: "Cabin")
        try await h.sites.save(cabin)
        let car = Location(siteID: site.id, name: "Car")
        let trunk = Location(siteID: cabin.id, name: "Cabin bag")
        try await h.locations.save(car)
        try await h.locations.save(trunk)
        var carKit = Kit(locationID: car.id, countsTowardSiteRunway: false)
        let cabinKit = Kit(locationID: trunk.id, lastInspectedDate: date(2026, 5, 1))
        try await h.kits.save(carKit)
        try await h.kits.save(cabinKit)
        #expect(try await h.kits.list(siteID: site.id) == [carKit])
        #expect(try await h.kits.list(siteID: cabin.id) == [cabinKit])

        carKit.countsTowardSiteRunway = true
        carKit.lastInspectedDate = date(2026, 6, 1)
        try await h.kits.save(carKit)
        #expect(try await h.kits.list(siteID: site.id) == [carKit])
    }

    @Test func savingMarksTheLocationAsTheKitAndKeepsItInSync() async throws {
        let h = try Harness()
        let site = try await h.sites.ensureDefaultSite()
        let car = Location(siteID: site.id, name: "Car")
        let bag = Location(siteID: site.id, name: "Go-bag")
        try await h.locations.save(car)
        try await h.locations.save(bag)
        var kit = Kit(locationID: car.id)
        try await h.kits.save(kit)
        #expect(try await h.locations.list(siteID: site.id).first { $0.id == car.id }?.kitID == kit.id)

        // The location read back can be saved again unchanged.
        try await h.locations.save(Location(
            id: car.id, siteID: site.id, name: "Car", kitID: kit.id))

        kit.locationID = bag.id
        try await h.kits.save(kit)
        let locations = try await h.locations.list(siteID: site.id)
        #expect(locations.first { $0.id == car.id }?.kitID == nil)
        #expect(locations.first { $0.id == bag.id }?.kitID == kit.id)
    }

    @Test func savingIntoMissingLocationThrowsTypedError() async throws {
        let h = try Harness()
        let ghost = LocationID()
        await #expect(throws: RepositoryError.locationNotFound(ghost)) {
            try await h.kits.save(Kit(locationID: ghost))
        }
    }
}

@Suite struct RunwayInputsLoaderTests {
    @Test func loadsEverythingForOneSiteAndNothingFromAnother() async throws {
        let h = try Harness()
        let seeded = try await h.seed()
        let ada = Person(siteID: seeded.site.id, name: "Ada")
        try await h.people.save(ada)
        let bag = Location(siteID: seeded.site.id, name: "Go-bag")
        try await h.locations.save(bag)
        let kit = Kit(locationID: bag.id)
        try await h.kits.save(kit)
        let spent = Harness.lot(seeded.rice, in: seeded.pantry, quantity: 3)
        try await h.lots.save(spent)
        try await h.lots.archive(spent.id)

        let cabin = Site(name: "Cabin")
        try await h.sites.save(cabin)
        let loft = Location(siteID: cabin.id, name: "Loft")
        try await h.locations.save(loft)
        try await h.locations.save(Location(siteID: cabin.id, name: "Cellar"))
        try await h.people.save(Person(siteID: cabin.id, name: "Bo"))
        try await h.lots.save(Harness.lot(seeded.rice, in: loft))
        try await h.kits.save(Kit(locationID: loft.id))

        let inputs = try await h.inputs.load(siteID: seeded.site.id)
        #expect(inputs.site == seeded.site)
        #expect(inputs.occupants == [ada])
        #expect(inputs.lots == [seeded.lot])
        #expect(inputs.products == [seeded.rice])
        #expect(Set(inputs.locations.map(\.name)) == ["Pantry", "Go-bag"])
        #expect(inputs.kits == [kit])
    }

    @Test func missingSiteThrowsTypedError() async throws {
        let h = try Harness()
        let id = SiteID()
        await #expect(throws: RepositoryError.siteNotFound(id)) { try await h.inputs.load(siteID: id) }
    }

    @Test func runwayFromLoadedInputsMatchesTheCalculatorOnTheSameValues() async throws {
        let h = try Harness()
        let seeded = try await h.seed()
        let ada = Person(siteID: seeded.site.id, name: "Ada", kcalPerDay: 2000)
        try await h.people.save(ada)
        let water = Product(
            name: "Water", category: .water, role: .supply, unitKind: .volume,
            potableWaterGalPerBaseUnit: 1, shelfLifeProfileKey: "bottled_water")
        try await h.products.save(water)
        let jugs = Lot(
            productID: water.id, quantity: 14, acquiredDate: date(2026, 1, 1), locationID: seeded.pantry.id)
        try await h.lots.save(jugs)

        let profiles = try ShelfLifeProfileTable.bundledDefaults()
        let today = date(2026, 2, 1)
        let loaded = RunwayCalculator.runway(
            for: try await h.inputs.load(siteID: seeded.site.id), profiles: profiles, on: today)
        let direct = RunwayCalculator.runway(
            for: seeded.site, occupants: [ada], lots: [seeded.lot, jugs], products: [seeded.rice, water],
            locations: [seeded.pantry], kits: [], profiles: profiles, on: today)
        #expect(loaded == direct)
        #expect(loaded.problems.isEmpty)
        #expect(loaded.food.highAmount == 16000)
        #expect(loaded.water.highAmount == 14)
    }
}
