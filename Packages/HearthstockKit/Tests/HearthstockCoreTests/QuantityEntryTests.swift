import Foundation
import Testing
@testable import HearthstockCore

@Suite struct QuantityEntryTests {
    @Test(arguments: [
        (QuantityEntry(value: 0.5, unit: .liter, packs: 24), UnitKind.volume, 3.170_06),  // a case of water
        (QuantityEntry(value: 20, unit: .pound), .mass, 20),
        (QuantityEntry(value: 9, unit: .kilogram), .mass, 19.841_6),
        (QuantityEntry(value: 6, unit: .count), .count, 6),
        (QuantityEntry(value: 2, unit: .count, packs: 12), .count, 24),
        (QuantityEntry(value: 1.5, unit: .kilowattHour), .energy, 1500),
        (QuantityEntry(value: 8, unit: .fluidOunce, packs: 1), .volume, 0.0625),
    ])
    func convertsToTheBaseUnit(entry: QuantityEntry, kind: UnitKind, expected: Double) throws {
        #expect(isApproximately(try entry.baseAmount(for: kind), expected, tolerance: 1e-4))
    }

    @Test(arguments: [
        (QuantityEntry(value: 0, unit: .pound), QuantityEntryError.invalidAmount),
        (QuantityEntry(value: -1, unit: .pound), .invalidAmount),
        (QuantityEntry(value: .nan, unit: .pound), .invalidAmount),
        (QuantityEntry(value: 1, unit: .pound, packs: 0), .invalidPacks),
        (QuantityEntry(value: 1, unit: .gallon), .wrongUnitKind(expected: .mass, got: .volume)),
    ])
    func refusesBadEntries(entry: QuantityEntry, error: QuantityEntryError) {
        #expect(throws: error) { try entry.baseAmount(for: .mass) }
    }

    @Test func zeroIsAllowedForARemainingQuantity() throws {
        #expect(try QuantityEntry(value: 0, unit: .ounce).baseAmount(for: .mass, allowZero: true) == 0)
    }

    @Test func adjustingToZeroArchivesAndBackUpRestores() {
        let lot = Lot(productID: ProductID(), quantity: 5, acquiredDate: date("2026-01-01"), locationID: LocationID())
        let empty = lot.adjusted(toRemaining: 0)
        #expect(empty.quantity == 0 && empty.archived)
        let refilled = empty.adjusted(toRemaining: 2)
        #expect(refilled.quantity == 2 && !refilled.archived)
        #expect(lot.adjusted(toRemaining: -3).archived)
    }
}

@Suite struct RunwayEffectTests {
    static let profiles = try! ShelfLifeProfileTable.bundledDefaults()

    @Test(arguments: [
        (1, RunwayEffect.counts(category: .food, amount: 33_000, unit: .kcal, lowEnd: true)),  // rice
        (2, .counts(category: .food, amount: 2_310, unit: .kcal, lowEnd: false)),  // Caution beans: high end only
        (7, .counts(category: .food, amount: 9_400, unit: .kcal, lowEnd: false)),  // Inspect peanut butter
        (6, .expired(category: .food)),  // flour
        (4, .expired(category: .water)),  // old tap water
        (9, .excludedByKit),  // go-bag MRE
        (13, .missingNutrition),  // jerky
        (16, .untreatedWater(gallons: 50)),  // rain barrel
        (15, .counts(category: .water, amount: 7, unit: .gallon, lowEnd: true)),
    ])
    func fixtureEffects(lot number: Int, effect: RunwayEffect) throws {
        let fixture = try PantryFixture.load()
        let status = try #require(fixture.statuses(profiles: Self.profiles).first { $0.lot == fixture.lot(number) })
        switch (RunwayEffect(status), effect) {
        case let (.counts(c1, a1, u1, l1), .counts(c2, a2, u2, l2)):
            #expect(c1 == c2 && u1 == u2 && l1 == l2)
            #expect(isApproximately(a1, a2, tolerance: 1e-6))
        case let (actual, expected):
            #expect(actual == expected)
        }
    }

    @Test func nonRunwayCategoriesSayNoRunway() throws {
        let site = Site(name: "Home")
        let shed = Location(siteID: site.id, name: "Shed")
        let radio = Product(
            name: "Radio", category: .tools, role: .supply, unitKind: .count, shelfLifeProfileKey: "honey_salt_sugar")
        let lot = Lot(productID: radio.id, quantity: 1, acquiredDate: date("2026-01-01"), locationID: shed.id)
        let status = LotStatusEvaluator.statuses(
            for: site, lots: [lot], products: [radio], locations: [shed], kits: [], profiles: Self.profiles,
            on: date("2026-10-06"))[0]
        #expect(RunwayEffect(status) == .noRunway(.tools))
    }
}

@Suite struct ShelfLifeTimelineTests {
    @Test func timelineMatchesTheStateBoundaries() throws {
        // Low-acid can printed 2026-01-01, climate controlled, 30-day notice: see ShelfLifeEvaluatorTests.
        let lot = Lot(
            productID: ProductID(), quantity: 1, acquiredDate: date("2025-01-01"), printedDate: date("2026-01-01"),
            locationID: LocationID())
        let profile = try #require(try ShelfLifeProfileTable.bundledDefaults()["canned_low_acid"])
        let result = ShelfLifeEvaluator.evaluate(
            lot, profile: profile, climate: .climateControlled, noticeWindowDays: 30, on: date("2026-06-01"))
        let timeline = try #require(result.timeline)
        #expect(timeline.goodThrough == date("2026-01-01"))
        #expect(timeline.useSoonFrom == date("2025-12-02"))
        #expect(timeline.inspectFrom == date("2027-08-09"))
        #expect(timeline.hasCaution && timeline.fromPrintedDate)
    }

    @Test func undatedLotsHaveNoTimeline() throws {
        let lot = Lot(productID: ProductID(), quantity: 1, acquiredDate: date("2025-01-01"), locationID: LocationID())
        let profile = try #require(try ShelfLifeProfileTable.bundledDefaults()["honey_salt_sugar"])
        #expect(ShelfLifeEvaluator.evaluate(lot, profile: profile, climate: .hot, on: date("2026-06-01")).timeline == nil)
    }
}
