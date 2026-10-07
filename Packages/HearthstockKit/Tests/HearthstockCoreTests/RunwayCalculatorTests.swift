import Foundation
import Testing
@testable import HearthstockCore

@Suite struct RunwayCalculatorTests {
    static let today = CalendarDate(iso: "2026-10-06")!
    static let profiles = try! ShelfLifeProfileTable.bundledDefaults()

    /// A one-site world with a climate-controlled pantry and a go-bag inside it.
    struct World {
        var site = Site(name: "Home")
        var pantry: Location
        var goBag: Location
        var kit: Kit
        var occupants: [Person]
        var products: [Product] = []
        var lots: [Lot] = []
        var extraLocations: [Location] = []

        init(kcalPerDay: [Double] = [2000], waterGalPerDay: Double = 1.0) {
            pantry = Location(siteID: site.id, name: "Pantry", climateClass: .climateControlled)
            let kitID = KitID()
            goBag = Location(siteID: site.id, name: "Go-bag", parentID: pantry.id, kitID: kitID)
            kit = Kit(id: kitID, locationID: goBag.id)
            let siteID = site.id
            occupants = kcalPerDay.enumerated().map { index, kcal in
                Person(siteID: siteID, name: "Person \(index + 1)", kcalPerDay: kcal, waterGalPerDay: waterGalPerDay)
            }
        }

        /// Adds a food product and one lot of it. `printed` controls the shelf-life state:
        /// canned low-acid, climate controlled, today 2026-10-06 → 2026-12-01 Good, 2026-01-01 Caution,
        /// 2024-12-01 Inspect, 2024-01-01 Expired.
        @discardableResult
        mutating func addFood(
            kcal: Double?, quantity: Double, printed: String = "2026-12-01", in location: Location? = nil
        ) -> Lot {
            let product = Product(
                name: "Food", category: .food, role: .supply, unitKind: .count, kcalPerBaseUnit: kcal,
                shelfLifeProfileKey: "canned_low_acid")
            products.append(product)
            let lot = Lot(
                productID: product.id, quantity: quantity, acquiredDate: CalendarDate(iso: "2024-01-01")!,
                printedDate: CalendarDate(iso: printed)!, locationID: (location ?? pantry).id)
            lots.append(lot)
            return lot
        }

        /// Adds a bottled-water product (gallons) and one lot of it. 24-month best-by, climate controlled:
        /// printed 2027-01-01 is Good today, 2025-06-01 Caution.
        @discardableResult
        mutating func addWater(gallons: Double, potable: Bool = true, printed: String = "2027-01-01") -> Lot {
            let product = Product(
                name: "Water", category: .water, role: .supply, unitKind: .volume,
                potableWaterGalPerBaseUnit: potable ? 1 : nil, shelfLifeProfileKey: "bottled_water")
            products.append(product)
            let lot = Lot(
                productID: product.id, quantity: gallons, acquiredDate: CalendarDate(iso: "2024-01-01")!,
                printedDate: CalendarDate(iso: printed)!, locationID: pantry.id)
            lots.append(lot)
            return lot
        }

        func runway() -> SiteRunway {
            RunwayCalculator.runway(
                for: site, occupants: occupants, lots: lots, products: products,
                locations: [pantry, goBag] + extraLocations, kits: [kit], profiles: profiles, on: today)
        }
    }

    // MARK: Basics

    @Test func singlePersonBasics() throws {
        var world = World()
        world.addFood(kcal: 1000, quantity: 20)  // 20,000 kcal / 2,000 = 10 days
        world.addWater(gallons: 7)  // 7 gal / 1 = 7 days
        let runway = world.runway()

        let food = try #require(runway.food.days)
        #expect(isApproximately(food.low, 10))
        #expect(isApproximately(food.high, 10))
        let water = try #require(runway.water.days)
        #expect(isApproximately(water.low, 7))
        let effective = try #require(runway.effective)
        #expect(isApproximately(effective.low, 7))
        #expect(isApproximately(effective.high, 7))
        #expect(runway.limitingCategory == .water)
        #expect(runway.problems.isEmpty)

        let target = try #require(runway.nextTarget)
        #expect(target.days == 14)
        #expect(target.category == .water)
        #expect(isApproximately(target.shortfall, 7))  // 14 gal needed, 7 on hand
    }

    @Test func twoPeopleWithDifferentKcalTargets() throws {
        var world = World(kcalPerDay: [2400, 2000])
        world.addFood(kcal: 2200, quantity: 10)  // 22,000 kcal / 4,400 = 5 days
        world.addWater(gallons: 30)  // 30 gal / 2 = 15 days
        let runway = world.runway()

        #expect(isApproximately(runway.food.dailyNeed, 4400))
        let food = try #require(runway.food.days)
        #expect(isApproximately(food.low, 5))
        #expect(runway.limitingCategory == .food)
        let target = try #require(runway.nextTarget)
        #expect(target.days == 14)
        #expect(isApproximately(target.shortfall, 14 * 4400 - 22000))
    }

    @Test(arguments: [
        ("2026-01-01", LotState.caution),
        ("2024-12-01", .inspect),
    ])
    func cautionAndInspectRaiseOnlyTheHighEnd(printed: String, state: LotState) throws {
        var world = World()
        let lot = world.addFood(kcal: 1000, quantity: 10, printed: printed)
        world.addFood(kcal: 1000, quantity: 20)
        let profile = try #require(Self.profiles["canned_low_acid"])
        #expect(
            ShelfLifeEvaluator.evaluate(lot, profile: profile, climate: .climateControlled, on: Self.today).state == state)

        let food = try #require(world.runway().food.days)
        #expect(isApproximately(food.low, 10))
        #expect(isApproximately(food.high, 15))
    }

    @Test func expiredNeverCounts() throws {
        var world = World()
        world.addFood(kcal: 1000, quantity: 10, printed: "2024-01-01")
        world.addFood(kcal: 1000, quantity: 20)
        let food = try #require(world.runway().food.days)
        #expect(isApproximately(food.low, 10))
        #expect(isApproximately(food.high, 10))
    }

    @Test func archivedLotsAreExcluded() throws {
        var world = World()
        world.addFood(kcal: 1000, quantity: 20)
        world.lots[0].archived = true
        world.addFood(kcal: 1000, quantity: 4)
        let food = try #require(world.runway().food.days)
        #expect(isApproximately(food.low, 2))
    }

    @Test func effectiveTakesLowAndHighSeparately() throws {
        var world = World()
        world.addFood(kcal: 1000, quantity: 10)  // food 5–25 days
        world.addFood(kcal: 1000, quantity: 40, printed: "2026-01-01")
        world.addWater(gallons: 8)  // water 8–8 days
        let runway = world.runway()
        let effective = try #require(runway.effective)
        #expect(isApproximately(effective.low, 5))
        #expect(isApproximately(effective.high, 8))
        #expect(runway.limitingCategory == .food)
    }

    // MARK: Kits and sites

    @Test func goBagExcludedByDefaultAndIncludedWhenFlagged() throws {
        var world = World()
        world.addFood(kcal: 1000, quantity: 20)
        world.addFood(kcal: 1000, quantity: 6, in: world.goBag)

        let excluded = try #require(world.runway().food.days)
        #expect(isApproximately(excluded.low, 10))

        world.kit.countsTowardSiteRunway = true
        let included = try #require(world.runway().food.days)
        #expect(isApproximately(included.low, 13))
    }

    @Test func lotInsideANestedKitLocationIsExcluded() throws {
        var world = World()
        let pouch = Location(siteID: world.site.id, name: "Food pouch", parentID: world.goBag.id)
        world.extraLocations = [pouch]
        world.addFood(kcal: 1000, quantity: 6, in: pouch)
        #expect(world.runway().food.lowAmount == 0)
    }

    @Test func lotAtAnotherSiteIsIgnored() throws {
        var world = World()
        let cabin = Site(name: "Cabin")
        let cabinShed = Location(siteID: cabin.id, name: "Shed", climateClass: .coolDry)
        world.extraLocations = [cabinShed]
        world.addFood(kcal: 1000, quantity: 20)
        world.addFood(kcal: 1000, quantity: 100, in: cabinShed)
        world.occupants.append(Person(siteID: cabin.id, name: "Cabin keeper", kcalPerDay: 3000))

        let runway = world.runway()
        #expect(isApproximately(runway.food.dailyNeed, 2000))
        let food = try #require(runway.food.days)
        #expect(isApproximately(food.low, 10))
        #expect(runway.problems.isEmpty)
    }

    // MARK: Problems

    @Test func zeroOccupants() {
        var world = World(kcalPerDay: [])
        world.addFood(kcal: 1000, quantity: 20)
        world.addWater(gallons: 5)
        let runway = world.runway()
        #expect(runway.problems == [.noOccupants])
        #expect(runway.food.days == nil)
        #expect(runway.water.days == nil)
        #expect(runway.effective == nil)
        #expect(runway.limitingCategory == nil)
        #expect(runway.nextTarget == nil)
        #expect(isApproximately(runway.food.lowAmount, 20000))
    }

    @Test func missingKcalLotIsReportedAndExcluded() throws {
        var world = World()
        world.addFood(kcal: 1000, quantity: 20)
        let unknown = world.addFood(kcal: nil, quantity: 50)
        let runway = world.runway()
        #expect(runway.lotsMissingNutrition == [unknown.id])
        let food = try #require(runway.food.days)
        #expect(isApproximately(food.high, 10))
    }

    @Test func unresolvableLotsAreReportedNotThrown() {
        var world = World()
        let lost = Lot(
            productID: ProductID(), quantity: 1, acquiredDate: Self.today, locationID: LocationID())
        let orphan = world.addFood(kcal: 1000, quantity: 1)
        world.products.removeAll()
        world.lots.append(lost)
        let runway = world.runway()
        #expect(runway.problems == [.missingProduct(orphan.id), .unresolvedLocation(lost.id)])
    }

    // MARK: Water

    @Test func nonPotableWaterIsReportedSeparately() throws {
        var world = World()
        world.addWater(gallons: 4)
        world.addWater(gallons: 50, potable: false)
        let runway = world.runway()
        #expect(isApproximately(runway.untreatedNonPotableGal, 50))
        let water = try #require(runway.water.days)
        #expect(isApproximately(water.high, 4))
    }

    @Test func waterCautionRaisesOnlyTheHighEnd() throws {
        var world = World()
        world.addWater(gallons: 4)
        world.addWater(gallons: 6, printed: "2025-06-01")
        let water = try #require(world.runway().water.days)
        #expect(isApproximately(water.low, 4))
        #expect(isApproximately(water.high, 10))
    }

    // MARK: Targets

    @Test(arguments: [
        (1.0, 3.0),  // below the first target
        (3.0, 14.0),  // exactly on a target: the next one is above it
        (20.0, 30.0),
    ])
    func nextTargetIsFirstAboveTheLowEnd(days: Double, expected: Double) throws {
        var world = World()
        world.addFood(kcal: 1000, quantity: 1000)
        world.addWater(gallons: days)
        let target = try #require(world.runway().nextTarget)
        #expect(target.days == expected)
        #expect(isApproximately(target.shortfall, expected - days))
    }

    @Test func noTargetOnceEveryTargetIsMet() {
        var world = World()
        world.addFood(kcal: 1000, quantity: 1000)
        world.addWater(gallons: 30)
        #expect(world.runway().nextTarget == nil)
    }

    // MARK: Overrides

    /// Canned low-acid printed 2024-10-06 in a climate-controlled pantry: 730 days, so today (2026-10-06)
    /// is its last usable day. Counted in `high`, never in `low`.
    private static let boundaryPrinted = "2024-10-06"

    @Test func locationMultiplierOverrideMovesALotAcrossTheBoundaryDay() {
        var world = World()
        world.addFood(kcal: 100, quantity: 10, printed: Self.boundaryPrinted)
        #expect(isApproximately(world.runway().food.highAmount, 1000))  // inspect on its last usable day

        world.pantry.climateMultiplierOverride = 0.99  // 730 × 0.99 → 722 days: expired 8 days ago
        #expect(isApproximately(world.runway().food.highAmount, 0))

        world.pantry.climateMultiplierOverride = 1.01  // 730 × 1.01 → 737 days: still inspect
        #expect(isApproximately(world.runway().food.highAmount, 1000))
    }

    @Test func locationMultiplierOverrideReplacesTheClassMultiplier() {
        // A hot (×0.5) pantry overridden to ×1.0 behaves as climate controlled.
        var world = World()
        world.pantry.climateClass = .hot
        world.addFood(kcal: 100, quantity: 10, printed: Self.boundaryPrinted)
        #expect(isApproximately(world.runway().food.highAmount, 0))
        world.pantry.climateMultiplierOverride = 1.0
        #expect(isApproximately(world.runway().food.highAmount, 1000))
    }

    @Test func lotsInheritTheirParentsMultiplierOverride() {
        var world = World()
        world.pantry.climateMultiplierOverride = 0.5
        let shelf = Location(siteID: world.site.id, name: "Shelf", parentID: world.pantry.id)
        world.extraLocations = [shelf]
        world.addFood(kcal: 100, quantity: 10, printed: Self.boundaryPrinted, in: shelf)
        #expect(isApproximately(world.runway().food.highAmount, 0))
    }

    @Test func aLotsOwnClimateOverrideBeatsTheLocationMultiplierOverride() {
        var world = World()
        world.pantry.climateMultiplierOverride = 0.5
        var lot = world.addFood(kcal: 100, quantity: 10, printed: Self.boundaryPrinted)
        #expect(isApproximately(world.runway().food.highAmount, 0))
        lot.climateOverride = .climateControlled
        world.lots[0] = lot
        #expect(isApproximately(world.runway().food.highAmount, 1000))
    }

    @Test func productOverrideChangesStateAndLotOverrideBeatsIt() {
        // Printed 2026-01-01 canned low-acid: Caution today. A 6-month product override expires it.
        var world = World()
        let lot = world.addFood(kcal: 100, quantity: 10, printed: "2026-01-01")
        let productID = lot.productID
        func runway(product: ShelfLifeOverride?, lot lotOverride: ShelfLifeOverride?) -> SiteRunway {
            RunwayCalculator.runway(
                for: world.site, occupants: world.occupants, lots: world.lots, products: world.products,
                locations: [world.pantry, world.goBag], kits: [world.kit],
                productShelfLifeOverrides: product.map { [productID: $0] } ?? [:],
                lotShelfLifeOverrides: lotOverride.map { [lot.id: $0] } ?? [:],
                profiles: Self.profiles, on: Self.today)
        }
        #expect(isApproximately(runway(product: nil, lot: nil).food.highAmount, 1000))
        #expect(isApproximately(runway(product: ShelfLifeOverride(extensionMonths: 6), lot: nil).food.highAmount, 0))
        let both = runway(product: ShelfLifeOverride(extensionMonths: 6), lot: ShelfLifeOverride(extensionMonths: 36))
        #expect(isApproximately(both.food.highAmount, 1000))
        #expect(both.problems.isEmpty)
    }

    @Test func overridesDoNotRescueAnUnknownProfileKey() {
        var world = World()
        let lot = world.addFood(kcal: 100, quantity: 10)
        world.products[0].shelfLifeProfileKey = "no_such_key"
        let runway = RunwayCalculator.runway(
            for: world.site, occupants: world.occupants, lots: world.lots, products: world.products,
            locations: [world.pantry, world.goBag], kits: [world.kit],
            productShelfLifeOverrides: [world.products[0].id: ShelfLifeOverride(extensionMonths: 6)],
            profiles: Self.profiles, on: Self.today)
        #expect(runway.problems == [.missingProfile(lot.id, "no_such_key")])
    }

    @Test func runwayInputsOverloadPassesOverridesThrough() {
        var world = World()
        let lot = world.addFood(kcal: 100, quantity: 10, printed: "2026-01-01")
        let inputs = RunwayInputs(
            site: world.site, occupants: world.occupants, lots: world.lots, products: world.products,
            locations: [world.pantry, world.goBag], kits: [world.kit],
            lotShelfLifeOverrides: [lot.id: ShelfLifeOverride(extensionMonths: 6)])
        #expect(isApproximately(RunwayCalculator.runway(for: inputs, profiles: Self.profiles, on: Self.today).food.highAmount, 0))
    }

    // MARK: Sample pantry

    /// Regression test for the runway math against a realistic pantry. Today is 2026-10-06; two adults
    /// need 2,400 + 2,000 = 4,400 kcal and 2 gal a day. Garage is hot (×0.5), hall closet cool-dry (×1.25),
    /// go-bag sits in the closet and doesn't count.
    ///
    /// Food, by hand:
    ///   Good     rice 20 lb × 1,650 (best-by 2027-06)                       33,000
    ///            Mylar pinto beans 25 lb × 1,570 (packed 2024-03, 120 mo)   39,250
    ///            honey 3 lb × 1,380 (no date)                                4,140
    ///            canned chicken 4 × 350 (best-by 2028-02)                    1,400
    ///            rolled oats 5 lb × 1,700 (best-by 2026-12)                  8,500
    ///                                                              low     86,290
    ///   Caution  black beans 6 × 385, printed 2025-08-06 (14 months ago),
    ///            usable to 2028-02-04 (730 × 1.25 → 912 days)                2,310
    ///   Inspect  peanut butter 2 × 4,700 in the garage, printed 2026-07-15,
    ///            usable to 2026-10-15 (184 × 0.5 → 92 days), inspect from 09-27  9,400
    ///                                                              high    98,000
    ///   Excluded flour (garage, expired 2026-08-01), tomatoes (garage, expired 2026-03-02),
    ///            MRE (go-bag), jerky (no kcal → lotsMissingNutrition), archived rice.
    ///   Days     86,290 / 4,400 = 19.61   98,000 / 4,400 = 22.27
    ///
    /// Water, by hand:
    ///   Good     bottled 3.17 gal (best-by 2027-03) + 7 gal jug filled 2026-07-01 (6-mo rotation)  10.17
    ///   Caution  bottled 3.17 gal, best-by 2025-01-01                                             3.17
    ///   Excluded 5 gal tap water filled 2026-02-06 (expired 2026-08-06); 50 gal rain barrel is non-potable.
    ///   Days     10.17 / 2 = 5.085   13.34 / 2 = 6.67
    ///
    /// Effective 5.085–6.67 days, limited by water; next target 14 days needs 28 − 10.17 = 17.83 gal.
    ///
    /// To use a different pantry, replace the fixture and its `expected` block; this test reads both.
    @Test func samplePantry() throws {
        let url = try #require(Bundle.module.url(forResource: "sample-pantry", withExtension: "json", subdirectory: "Fixtures"))
        let fixture = try JSONDecoder().decode(PantryFixture.self, from: Data(contentsOf: url))
        let expected = fixture.expected

        let runway = RunwayCalculator.runway(
            for: fixture.site, occupants: fixture.occupants, lots: fixture.lots, products: fixture.products,
            locations: fixture.locations, kits: fixture.kits, profiles: Self.profiles, on: fixture.today)

        #expect(runway.problems.isEmpty)
        #expect(isApproximately(runway.food.lowAmount, expected.foodKcalLow, tolerance: 1e-6))
        #expect(isApproximately(runway.food.highAmount, expected.foodKcalHigh, tolerance: 1e-6))
        #expect(isApproximately(runway.water.lowAmount, expected.waterGalLow, tolerance: 1e-6))
        #expect(isApproximately(runway.water.highAmount, expected.waterGalHigh, tolerance: 1e-6))

        let food = try #require(runway.food.days)
        #expect(isApproximately(food.low, expected.foodDaysLow, tolerance: 1e-6))
        #expect(isApproximately(food.high, expected.foodDaysHigh, tolerance: 1e-6))
        let water = try #require(runway.water.days)
        #expect(isApproximately(water.low, expected.waterDaysLow, tolerance: 1e-6))
        #expect(isApproximately(water.high, expected.waterDaysHigh, tolerance: 1e-6))

        let effective = try #require(runway.effective)
        #expect(isApproximately(effective.low, min(expected.foodDaysLow, expected.waterDaysLow), tolerance: 1e-6))
        #expect(isApproximately(effective.high, min(expected.foodDaysHigh, expected.waterDaysHigh), tolerance: 1e-6))
        #expect(runway.limitingCategory?.rawValue == expected.limitingCategory)

        let target = try #require(runway.nextTarget)
        #expect(target.days == expected.nextTargetDays)
        #expect(target.category.rawValue == expected.limitingCategory)
        #expect(isApproximately(target.shortfall, expected.nextTargetShortfall, tolerance: 1e-6))

        #expect(isApproximately(runway.untreatedNonPotableGal, expected.untreatedNonPotableGal, tolerance: 1e-6))
        #expect(runway.lotsMissingNutrition == expected.lotsMissingNutrition)
    }
}

/// `Fixtures/sample-pantry.json`: one site's world plus the hand-computed results.
struct PantryFixture: Decodable {
    struct Expected: Decodable {
        var foodKcalLow: Double
        var foodKcalHigh: Double
        var waterGalLow: Double
        var waterGalHigh: Double
        var foodDaysLow: Double
        var foodDaysHigh: Double
        var waterDaysLow: Double
        var waterDaysHigh: Double
        var limitingCategory: String
        var nextTargetDays: Double
        var nextTargetShortfall: Double
        var untreatedNonPotableGal: Double
        var lotsMissingNutrition: [LotID]
    }

    var today: CalendarDate
    var site: Site
    var occupants: [Person]
    var locations: [Location]
    var kits: [Kit]
    var products: [Product]
    var lots: [Lot]
    var expected: Expected
}
