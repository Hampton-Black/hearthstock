import Foundation
import Testing
@testable import HearthstockCore

@Suite struct FocusNextTests {
    static let profiles = try! ShelfLifeProfileTable.bundledDefaults()
    static let today = date("2026-10-06")

    /// A climate-controlled pantry with one person (2,000 kcal, 1 gal a day).
    struct World {
        var site = Site(name: "Home")
        var pantry: Location
        var occupants: [Person]
        var products: [Product] = []
        var lots: [Lot] = []

        init(people: Int = 1) {
            pantry = Location(siteID: site.id, name: "Pantry", climateClass: .climateControlled)
            let siteID = site.id
            occupants = (0..<people).map { Person(siteID: siteID, name: "Person \($0 + 1)") }
        }

        /// Canned low-acid (24-month best-by): printed 2026-10-20 is Use soon, 2026-01-01 Caution, 2024-12-01
        /// Inspect, 2024-01-01 Expired, 2027-06-01 Good.
        @discardableResult
        mutating func addFood(_ name: String, kcal: Double? = 1000, quantity: Double = 10, printed: String) -> Lot {
            let product = Product(
                name: name, category: .food, role: .supply, unitKind: .count, kcalPerBaseUnit: kcal,
                shelfLifeProfileKey: "canned_low_acid")
            products.append(product)
            let lot = Lot(
                productID: product.id, quantity: quantity, acquiredDate: date("2024-01-01"),
                printedDate: date(printed), locationID: pantry.id)
            lots.append(lot)
            return lot
        }

        mutating func addWater(gallons: Double) {
            let product = Product(
                name: "Water", category: .water, role: .supply, unitKind: .volume, potableWaterGalPerBaseUnit: 1,
                shelfLifeProfileKey: "bottled_water")
            products.append(product)
            lots.append(Lot(
                productID: product.id, quantity: gallons, acquiredDate: date("2026-01-01"),
                printedDate: date("2028-01-01"), locationID: pantry.id))
        }

        func items() -> [FocusItem] {
            let inputs = RunwayInputs(
                site: site, occupants: occupants, lots: lots, products: products, locations: [pantry], kits: [])
            return FocusNext.items(
                runway: RunwayCalculator.runway(for: inputs, profiles: profiles, on: today),
                statuses: LotStatusEvaluator.statuses(for: inputs, profiles: profiles, on: today))
        }
    }

    @Test func limitingCategoryItemUsesTheNextTargetsShortfall() throws {
        var world = World()
        world.addFood("Rice", quantity: 100, printed: "2027-06-01")  // 50 days
        world.addWater(gallons: 5)  // 5 days → next target 14 needs 9 more gallons
        let first = try #require(world.items().first)
        guard case let .reachTarget(category, amount, unit, targetDays) = first else {
            Issue.record("expected a target item, got \(first)")
            return
        }
        #expect(category == .water)
        #expect(unit == .gallon)
        #expect(targetDays == 14)
        #expect(isApproximately(amount, 9))
    }

    @Test func foodTargetIsInKcal() throws {
        var world = World()
        world.addFood("Rice", quantity: 2, printed: "2027-06-01")  // 2,000 kcal = 1 day
        world.addWater(gallons: 40)
        guard case let .reachTarget(category, amount, unit, targetDays)? = world.items().first else {
            Issue.record("expected a target item")
            return
        }
        #expect(category == .food)
        #expect(unit == .kcal)
        #expect(targetDays == 3)
        #expect(isApproximately(amount, 4000))
    }

    @Test func noTargetItemOncePastTheLastTarget() {
        var world = World()
        world.addFood("Rice", quantity: 100, printed: "2027-06-01")
        world.addWater(gallons: 40)
        #expect(world.items().isEmpty)
    }

    @Test func cautionAndInspectByUsableByThenUseSoonByPrintedDate() {
        var world = World()
        world.addFood("Rice", quantity: 100, printed: "2027-06-01")
        world.addWater(gallons: 40)
        let caution = world.addFood("Beans", printed: "2026-01-01")  // usable to 2028-01-01
        let inspect = world.addFood("Corn", printed: "2024-12-01")  // usable to 2026-12-01
        let soonLater = world.addFood("Peas", printed: "2026-10-30")
        let soonFirst = world.addFood("Soup", printed: "2026-10-10")
        world.addFood("Old tuna", printed: "2024-01-01")  // expired: not listed

        let items = world.items()
        #expect(items.count == 4)
        let ids: [LotID] = items.compactMap {
            switch $0 {
            case .rotate(let status), .useSoon(let status): status.lot.id
            default: nil
            }
        }
        #expect(ids == [inspect.id, caution.id, soonFirst.id, soonLater.id])
        if case .rotate = items[0], case .rotate = items[1], case .useSoon = items[2], case .useSoon = items[3] {
        } else {
            Issue.record("wrong item kinds: \(items)")
        }
    }

    @Test func tiesAreBrokenByProductName() {
        var world = World()
        world.addFood("Rice", quantity: 100, printed: "2027-06-01")
        world.addWater(gallons: 40)
        let zucchini = world.addFood("Zucchini", printed: "2026-01-01")
        let apples = world.addFood("Apples", printed: "2026-01-01")
        let items = world.items()
        #expect(items == [
            .rotate(LotStatusEvaluator.statuses(
                for: world.site, lots: [apples], products: world.products, locations: [world.pantry], kits: [],
                profiles: Self.profiles, on: Self.today)[0]),
            .rotate(LotStatusEvaluator.statuses(
                for: world.site, lots: [zucchini], products: world.products, locations: [world.pantry], kits: [],
                profiles: Self.profiles, on: Self.today)[0]),
        ])
    }

    @Test func expiredLotsAreNotEatOrRotate() {
        var world = World()
        world.addFood("Rice", quantity: 100, printed: "2027-06-01")
        world.addWater(gallons: 40)
        world.addFood("Old tuna", printed: "2024-01-01")
        #expect(world.items().isEmpty)
    }

    @Test func zeroOccupantsPutsTheProblemFirst() {
        var world = World(people: 0)
        world.addFood("Beans", printed: "2026-01-01")
        let items = world.items()
        #expect(items.first == .noOccupants)
        #expect(items.count == 2)
        if case .rotate = items[1] {} else { Issue.record("expected the Caution lot after the problem") }
    }

    @Test func missingNutritionAndWaterVolumeAreOneItemEach() {
        var world = World()
        world.addFood("Rice", quantity: 100, printed: "2027-06-01")
        world.addWater(gallons: 40)
        let jerkyA = world.addFood("Jerky", kcal: nil, printed: "2027-06-01")
        let jerkyB = Lot(
            productID: jerkyA.productID, quantity: 1, acquiredDate: date("2026-01-01"),
            printedDate: date("2027-06-01"), locationID: world.pantry.id)
        world.lots.append(jerkyB)
        let cases = Product(
            name: "Water cases", category: .water, role: .supply, unitKind: .count, shelfLifeProfileKey: "bottled_water")
        world.products.append(cases)
        let caseLot = Lot(
            productID: cases.id, quantity: 2, acquiredDate: date("2026-01-01"), printedDate: date("2028-01-01"),
            locationID: world.pantry.id)
        world.lots.append(caseLot)

        #expect(world.items() == [
            .missingNutrition(lots: [jerkyA.id, jerkyB.id], products: [jerkyA.productID]),
            .missingWaterVolume(lots: [caseLot.id], products: [cases.id]),
        ])
    }

    @Test func samplePantryProducesTheExpectedList() throws {
        let fixture = try PantryFixture.load()
        let inputs = fixture.inputs()
        let items = FocusNext.items(
            runway: RunwayCalculator.runway(for: inputs, profiles: Self.profiles, on: fixture.today),
            statuses: LotStatusEvaluator.statuses(for: inputs, profiles: Self.profiles, on: fixture.today))

        #expect(items.count == 5)
        guard case let .reachTarget(category, amount, unit, targetDays) = items[0] else {
            Issue.record("expected the water target first, got \(items[0])")
            return
        }
        #expect(category == .water && unit == .gallon && targetDays == 14)
        #expect(isApproximately(amount, fixture.expected.nextTargetShortfall, tolerance: 1e-6))

        // Peanut butter (Inspect, usable to 2026-10-15), the old bottled water (Caution, 2027), then the
        // 14-month-old black beans (Caution, usable to 2028-02-04).
        let rotated: [Lot] = items[1...3].compactMap { if case .rotate(let s) = $0 { s.lot } else { nil } }
        #expect(rotated == [fixture.lot(7), fixture.lot(14), fixture.lot(2)])
        #expect(items[4] == .missingNutrition(lots: [fixture.lot(13).id], products: [fixture.lot(13).productID]))
    }
}
