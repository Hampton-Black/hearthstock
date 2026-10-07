import Foundation
import Testing
@testable import HearthstockCore

@Suite struct LotStatusTests {
    static let profiles = try! ShelfLifeProfileTable.bundledDefaults()

    // MARK: Sample pantry

    /// Every unarchived fixture lot's state on 2026-10-06, by hand (see `RunwayCalculatorTests.samplePantry`
    /// for the windows). The garage is hot and humid, so its unsealed lots carry `humidityRisk`. No fixture lot
    /// is within 30 days of its printed date, so none is Use soon.
    static let expectedStates: [(lot: Int, state: LotState, flags: Set<LotFlag>)] = [
        (1, .good, [.humidityRisk]),  // rice, garage, best-by 2027-06-01
        (2, .caution, []),  // black beans printed 14 months ago, cool-dry closet
        (3, .good, []),  // bottled water, best-by 2027-03-01
        (4, .expired, [.humidityRisk]),  // 5 gal tap water filled 2026-02-06, 6-month rotation
        (5, .good, []),  // Mylar pinto beans, no printed date: packed-life window, so no missing-date flag
        (6, .expired, [.humidityRisk]),  // flour, garage
        (7, .inspect, [.humidityRisk]),  // peanut butter, garage
        (8, .good, []),  // honey, never expires
        (9, .good, []),  // MRE in the go-bag
        (10, .good, []),  // canned chicken
        (11, .good, []),  // rolled oats, best-by 2026-12-01: 56 days out, outside the notice window
        (12, .expired, [.humidityRisk]),  // diced tomatoes, garage
        (13, .good, [.missingDate]),  // homemade jerky, no printed date and no rotation rule
        (14, .caution, []),  // bottled water, best-by 2025-01-01
        (15, .good, []),  // 7 gal jug filled 2026-07-01
        (16, .good, [.humidityRisk]),  // rain barrel, garage
    ]

    @Test(arguments: expectedStates)
    func fixtureLotStates(lot number: Int, state: LotState, flags: Set<LotFlag>) throws {
        let fixture = try PantryFixture.load()
        let status = try #require(fixture.statuses(profiles: Self.profiles).first { $0.lot == fixture.lot(number) })
        #expect(status.state == state)
        #expect(status.evaluation?.flags == flags)
        #expect(status.problem == nil)
    }

    @Test func fixtureHasOneStatusPerUnarchivedLotInOrder() throws {
        let fixture = try PantryFixture.load()
        let statuses = fixture.statuses(profiles: Self.profiles)
        #expect(statuses.map(\.lot) == fixture.lots.filter { !$0.archived })
        #expect(statuses.count == Self.expectedStates.count)
    }

    @Test func goBagMREIsExcludedFromRunwayAndEverythingElseCounts() throws {
        let fixture = try PantryFixture.load()
        let statuses = fixture.statuses(profiles: Self.profiles)
        let excluded = statuses.filter { !$0.countsTowardSiteRunway }.map(\.lot)
        #expect(excluded == [fixture.lot(9)])
        let mre = try #require(statuses.first { $0.lot == fixture.lot(9) })
        #expect(mre.kitLocation?.name == "Go-bag")
        #expect(mre.locationChain.map(\.name) == ["Go-bag", "Hall closet"])
        #expect(mre.climate == .coolDry)  // inherited from the closet
    }

    @Test func statusCarriesTheResolvedClimateProfileAndUsableBy() throws {
        let fixture = try PantryFixture.load()
        let beans = try #require(fixture.statuses(profiles: Self.profiles).first { $0.lot == fixture.lot(2) })
        #expect(beans.product?.name == "Black beans, 15 oz can")
        #expect(beans.climate == .coolDry)
        #expect(beans.humidity == .dry)
        #expect(beans.windowMultiplierOverride == nil)
        #expect(beans.profile?.key == "canned_low_acid")
        #expect(beans.evaluation?.usableBy == date("2028-02-04"))
    }

    @Test func statesMatchWhatTheRunwayCounted() throws {
        // The low end is the in-date lots, the high end adds Caution and Inspect: recomputing food from the
        // statuses gives the calculator's numbers.
        let fixture = try PantryFixture.load()
        let statuses = fixture.statuses(profiles: Self.profiles)
        let runway = RunwayCalculator.runway(for: fixture.inputs(), profiles: Self.profiles, on: fixture.today)
        var low = 0.0, high = 0.0
        for status in statuses where status.countsTowardSiteRunway && status.product?.category == .food {
            guard let kcal = status.product?.kcalPerBaseUnit, let state = status.state else { continue }
            let amount = status.lot.quantity * kcal
            switch state {
            case .good, .useSoon: low += amount; high += amount
            case .caution, .inspect: high += amount
            case .expired: break
            }
        }
        #expect(isApproximately(low, runway.food.lowAmount, tolerance: 1e-6))
        #expect(isApproximately(high, runway.food.highAmount, tolerance: 1e-6))
    }

    // MARK: Problems and other sites

    @Test func lotAtAnotherSiteIsAbsent() throws {
        let fixture = try PantryFixture.load()
        let cabin = Site(name: "Cabin")
        let shed = Location(siteID: cabin.id, name: "Shed")
        let cabinLot = Lot(
            productID: fixture.products[0].id, quantity: 5, acquiredDate: date("2026-01-01"), locationID: shed.id)
        let statuses = LotStatusEvaluator.statuses(
            for: fixture.site, lots: fixture.lots + [cabinLot], products: fixture.products,
            locations: fixture.locations + [shed], kits: fixture.kits, profiles: Self.profiles, on: fixture.today)
        #expect(!statuses.contains { $0.lot == cabinLot })
        #expect(statuses.count == Self.expectedStates.count)
    }

    @Test func missingProductIsReportedNotDropped() throws {
        let fixture = try PantryFixture.load()
        let orphan = Lot(
            productID: ProductID(), quantity: 1, acquiredDate: date("2026-01-01"),
            locationID: fixture.locations[0].id)
        let statuses = LotStatusEvaluator.statuses(
            for: fixture.site, lots: [orphan], products: fixture.products, locations: fixture.locations,
            kits: fixture.kits, profiles: Self.profiles, on: fixture.today)
        let status = try #require(statuses.first)
        #expect(status.problem == .missingProduct(orphan.id))
        #expect(status.product == nil)
        #expect(status.evaluation == nil)
        #expect(status.locationChain.map(\.name) == ["Garage shelf"])
    }

    @Test func unresolvedLocationAndMissingProfileAreReported() throws {
        let fixture = try PantryFixture.load()
        let lost = Lot(
            productID: fixture.products[0].id, quantity: 1, acquiredDate: date("2026-01-01"), locationID: LocationID())
        let tool = Product(
            name: "Hand crank radio", category: .tools, role: .supply, unitKind: .count,
            shelfLifeProfileKey: "no_such_profile")
        let radio = Lot(
            productID: tool.id, quantity: 1, acquiredDate: date("2026-01-01"), locationID: fixture.locations[1].id)
        let statuses = LotStatusEvaluator.statuses(
            for: fixture.site, lots: [lost, radio], products: fixture.products + [tool],
            locations: fixture.locations, kits: fixture.kits, profiles: Self.profiles, on: fixture.today)
        #expect(statuses.map(\.problem) == [.unresolvedLocation(lost.id), .missingProfile(radio.id, "no_such_profile")])
        #expect(statuses.allSatisfy { $0.evaluation == nil })
        #expect(statuses[1].countsTowardSiteRunway)

        // A tool with no profile is not a runway problem: the runway only reports what it would count.
        let runway = RunwayCalculator.runway(
            for: fixture.site, occupants: fixture.occupants, lots: [lost, radio], products: fixture.products + [tool],
            locations: fixture.locations, kits: fixture.kits, profiles: Self.profiles, on: fixture.today)
        #expect(runway.problems == [.unresolvedLocation(lost.id)])
    }

    @Test func siteDecodedWithoutANoticeWindowGetsTheDefault() throws {
        let site = try JSONDecoder().decode(
            Site.self, from: Data(#"{"id": "00000001-0000-0000-0000-000000000001", "name": "Home"}"#.utf8))
        #expect(site.noticeWindowDays == 30)
        let custom = Site(name: "Cabin", noticeWindowDays: 14)
        #expect(try JSONDecoder().decode(Site.self, from: JSONEncoder().encode(custom)) == custom)
    }
}

@Suite struct UseSoonTests {
    static func profile(_ key: ShelfLifeProfileKey) -> ShelfLifeProfile {
        try! ShelfLifeProfileTable.bundledDefaults()[key]!
    }

    static func state(
        printed: String, profile key: ShelfLifeProfileKey = "canned_low_acid", window: Int = 30, on today: String
    ) -> LotState {
        let lot = Lot(
            productID: ProductID(), quantity: 1, acquiredDate: date("2025-01-01"), printedDate: date(printed),
            locationID: LocationID())
        return ShelfLifeEvaluator.evaluate(
            lot, profile: profile(key), climate: .climateControlled, noticeWindowDays: window, on: date(today)
        ).state
    }

    /// Best-by can printed 2026-01-01 with a 30-day window: Use soon from 2025-12-02 through the printed date.
    @Test(arguments: [
        ("2025-12-01", LotState.good),  // 31 days out
        ("2025-12-02", .useSoon),  // the day the window opens, 30 days out
        ("2025-12-20", .useSoon),
        ("2026-01-01", .useSoon),  // the printed date itself
        ("2026-01-02", .caution),
        ("2027-08-09", .inspect),
        ("2028-01-02", .expired),
    ])
    func bestByGoesGoodUseSoonCautionInspectExpired(today: String, expected: LotState) {
        #expect(Self.state(printed: "2026-01-01", on: today) == expected)
    }

    /// Use-by formula printed 2026-10-05 skips Caution and Inspect.
    @Test(arguments: [
        ("2026-09-04", LotState.good),
        ("2026-09-05", .useSoon),
        ("2026-10-05", .useSoon),
        ("2026-10-06", .expired),
    ])
    func useByGoesFromUseSoonStraightToExpired(today: String, expected: LotState) {
        #expect(Self.state(printed: "2026-10-05", profile: "infant_formula", on: today) == expected)
    }

    @Test(arguments: [
        (7, "2025-12-24", LotState.good),
        (7, "2025-12-25", .useSoon),
        (90, "2025-10-03", .useSoon),
        (90, "2025-10-02", .good),
        (0, "2026-01-01", .good),  // no window: Slice 1 behaviour
    ])
    func windowLengthMovesTheOpeningDay(window: Int, today: String, expected: LotState) {
        #expect(Self.state(printed: "2026-01-01", window: window, on: today) == expected)
    }

    @Test func noPrintedDateIsGoodNotUseSoon() {
        let can = Lot(productID: ProductID(), quantity: 1, acquiredDate: date("2026-01-01"), locationID: LocationID())
        let result = ShelfLifeEvaluator.evaluate(
            can, profile: Self.profile("canned_low_acid"), climate: .climateControlled, noticeWindowDays: 30,
            on: date("2026-01-01"))
        #expect(result.state == .good)
    }

    @Test func packagedWindowIgnoresAnUpcomingPrintedDate() {
        // Mylar rice ages by its packing date, so its printed date doesn't start a notice window.
        let rice = Lot(
            productID: ProductID(), quantity: 1, acquiredDate: date("2024-01-01"), printedDate: date("2026-01-10"),
            packaging: .mylarO2, locationID: LocationID())
        let result = ShelfLifeEvaluator.evaluate(
            rice, profile: Self.profile("white_rice"), climate: .climateControlled, noticeWindowDays: 30,
            on: date("2026-01-01"))
        #expect(result.state == .good)
    }

    @Test func useSoonLotsCountTowardBothEnds() throws {
        let site = Site(name: "Home")
        let pantry = Location(siteID: site.id, name: "Pantry", climateClass: .climateControlled)
        let can = Product(
            name: "Beans", category: .food, role: .supply, unitKind: .count, kcalPerBaseUnit: 1000,
            shelfLifeProfileKey: "canned_low_acid")
        let soon = Lot(
            productID: can.id, quantity: 10, acquiredDate: date("2025-01-01"), printedDate: date("2026-10-20"),
            locationID: pantry.id)
        let later = Lot(
            productID: can.id, quantity: 10, acquiredDate: date("2025-01-01"), printedDate: date("2027-10-20"),
            locationID: pantry.id)
        let runway = RunwayCalculator.runway(
            for: site, occupants: [Person(siteID: site.id, name: "A")], lots: [soon, later], products: [can],
            locations: [pantry], kits: [], profiles: try ShelfLifeProfileTable.bundledDefaults(),
            on: date("2026-10-06"))
        let statuses = LotStatusEvaluator.statuses(
            for: site, lots: [soon, later], products: [can], locations: [pantry], kits: [],
            profiles: try ShelfLifeProfileTable.bundledDefaults(), on: date("2026-10-06"))
        #expect(statuses.map(\.state) == [.useSoon, .good])
        #expect(isApproximately(runway.food.lowAmount, 20_000))
        #expect(isApproximately(runway.food.highAmount, 20_000))
    }
}
