import Foundation
import Testing
@testable import HearthstockCore

/// Slice 4 Decisions 1–4: a lot either has a printed date, is marked "no printed date" and ages from an estimate, or
/// is flagged as missing one.
@Suite struct UndatedLotTests {
    static let table = try! ShelfLifeProfileTable.bundledDefaults()
    static func date(_ iso: String) -> CalendarDate { CalendarDate(iso: iso)! }
    static func profile(_ key: ShelfLifeProfileKey) -> ShelfLifeProfile { table[key]! }

    static func lot(acquired: String = "2025-01-01", printed: String? = nil, noPrintedDate: Bool = false,
                    packaging: Packaging = .none) -> Lot {
        Lot(productID: ProductID(), quantity: 1, acquiredDate: date(acquired), printedDate: printed.map(date),
            noPrintedDate: noPrintedDate, packaging: packaging, locationID: LocationID())
    }

    static func evaluate(_ lot: Lot, _ profile: ShelfLifeProfile, climate: ClimateClass = .climateControlled,
                         on today: String) -> ShelfLifeEvaluation {
        ShelfLifeEvaluator.evaluate(lot, profile: profile, climate: climate, on: date(today))
    }

    // MARK: The three cases

    enum Case: String, CaseIterable { case printed, missing, estimated }

    static func lot(_ dateCase: Case) -> Lot {
        switch dateCase {
        case .printed: lot(printed: "2026-06-01")
        case .missing: lot()
        case .estimated: lot(noPrintedDate: true)
        }
    }

    /// Canned low acid (best by, 24-month extension, 24-month estimate) on 2025-06-01.
    @Test(arguments: [
        (Case.printed, LotState.good, "2028-06-01", Set<LotFlag>()),
        (.missing, .good, nil, [.missingDate]),
        (.estimated, .good, "2027-01-01", [.estimatedDate]),
    ] as [(Case, LotState, String?, Set<LotFlag>)])
    func bestBy(dateCase: Case, state: LotState, usableBy: String?, flags: Set<LotFlag>) {
        let result = Self.evaluate(Self.lot(dateCase), Self.profile("canned_low_acid"), on: "2025-06-01")
        #expect(result.state == state)
        #expect(result.usableBy == usableBy.map(Self.date))
        #expect(result.flags == flags)
        #expect(result.timeline?.isEstimate == (dateCase == .estimated ? true : dateCase == .printed ? false : nil))
    }

    /// Medication (use by, 12-month estimate) on 2025-06-01.
    @Test(arguments: [
        (Case.printed, LotState.good, "2026-06-01", Set<LotFlag>()),
        (.missing, .good, nil, [.missingDate]),
        (.estimated, .good, "2026-01-01", [.estimatedDate]),
    ] as [(Case, LotState, String?, Set<LotFlag>)])
    func useBy(dateCase: Case, state: LotState, usableBy: String?, flags: Set<LotFlag>) {
        let result = Self.evaluate(Self.lot(dateCase), Self.profile("medication"), on: "2025-06-01")
        #expect(result.state == state)
        #expect(result.usableBy == usableBy.map(Self.date))
        #expect(result.flags == flags)
    }

    /// Profiles with date type none ignore the flag and age exactly as before.
    @Test(arguments: Case.allCases)
    func noDateProfilesIgnoreTheFlag(dateCase: Case) {
        let honey = Self.evaluate(Self.lot(dateCase), Self.profile("honey_salt_sugar"), on: "2030-01-01")
        #expect(honey.state == .good)
        #expect(honey.usableBy == nil)
        #expect(honey.flags.isEmpty)

        let water = Self.evaluate(Self.lot(dateCase), Self.profile("stored_tap_water"), on: "2025-03-01")
        #expect(water.usableBy == Self.date("2025-07-01"))
        #expect(water.flags.isEmpty)
    }

    // MARK: The estimated window

    /// 730 days from 2025-01-01; the last 20% (146 days) is Inspect, with no Caution and no Use soon.
    @Test(arguments: [
        ("2025-01-01", LotState.good),
        ("2026-08-08", .good),
        ("2026-08-09", .inspect),
        ("2027-01-01", .inspect),
        ("2027-01-02", .expired),
    ])
    func estimateAgesGoodThenInspectThenExpired(today: String, state: LotState) {
        let lot = Self.lot(noPrintedDate: true)
        let result = ShelfLifeEvaluator.evaluate(
            lot, profile: Self.profile("canned_low_acid"), climate: .climateControlled, noticeWindowDays: 30,
            on: Self.date(today))
        #expect(result.state == state)
        #expect(result.timeline?.inspectFrom == Self.date("2026-08-09"))
        #expect(result.timeline?.useSoonFrom == nil)
        #expect(result.timeline?.hasCaution == false)
    }

    /// Profile months are at baseline climate, so a hot garage halves the estimate as it does a printed window.
    @Test func climateScalesTheEstimate() {
        let result = Self.evaluate(
            Self.lot(noPrintedDate: true), Self.profile("canned_low_acid"), climate: .hot, on: "2025-06-01")
        #expect(result.usableBy == Self.date("2026-01-01"))
    }

    @Test func aLotOverrideOfTheMonthsMovesTheEstimate() throws {
        let product = Product(
            name: "Beans", category: .food, role: .supply, unitKind: .count, shelfLifeProfileKey: "canned_low_acid")
        let lot = Lot(productID: product.id, quantity: 1, acquiredDate: Self.date("2025-01-01"), noPrintedDate: true,
                      locationID: LocationID())
        let resolver = ShelfLifeProfileResolver(table: Self.table, lotOverrides: [lot.id: ShelfLifeOverride(rotationMonths: 36)])
        let profile = try #require(resolver.profile(for: lot, product: product))
        #expect(Self.evaluate(lot, profile, on: "2025-06-01").usableBy == Self.date("2028-01-01"))
    }

    @Test func anEstimatedLotCountsInTheLowEndUntilInspect() {
        let site = Site(name: "Home")
        let pantry = Location(siteID: site.id, name: "Pantry", climateClass: .climateControlled)
        let product = Product(
            name: "Beans", category: .food, role: .supply, unitKind: .count, kcalPerBaseUnit: 400,
            shelfLifeProfileKey: "canned_low_acid")
        let lot = Lot(productID: product.id, quantity: 10, acquiredDate: Self.date("2025-01-01"), noPrintedDate: true,
                      locationID: pantry.id)
        let inputs = RunwayInputs(
            site: site, occupants: [Person(siteID: site.id, name: "A")], lots: [lot], products: [product],
            locations: [pantry], kits: [])
        func effect(_ today: String) -> RunwayEffect? {
            LotStatusEvaluator.statuses(for: inputs, profiles: Self.table, on: Self.date(today)).first
                .map { RunwayEffect($0) }
        }
        #expect(effect("2026-08-08") == .counts(category: .food, amount: 4000, unit: .kcal, lowEnd: true))
        #expect(effect("2026-08-09") == .counts(category: .food, amount: 4000, unit: .kcal, lowEnd: false))
        #expect(effect("2027-01-02") == .expired(category: .food))
    }

    /// White rice in Mylar: 120 months packaged beats the 60-month estimate, so it's dated by its packaging.
    @Test(arguments: [false, true])
    func mylarWithoutADateUsesItsPackagedLife(noPrintedDate: Bool) {
        let rice = Self.lot(acquired: "2024-01-01", noPrintedDate: noPrintedDate, packaging: .mylarO2)
        let result = Self.evaluate(rice, Self.profile("white_rice"), on: "2026-10-06")
        #expect(result.flags.isEmpty)
        #expect(result.usableBy == Self.date("2034-01-01"))
    }

    /// With a lot override shortening the packaged life below the estimate, the estimate wins and is flagged.
    @Test func theLongerOfPackagedLifeAndEstimateWins() {
        var profile = Self.profile("white_rice")
        profile.packagedLifeMonths = 12
        let rice = Self.lot(acquired: "2024-01-01", noPrintedDate: true, packaging: .bucket)
        let result = Self.evaluate(rice, profile, on: "2026-10-06")
        #expect(result.usableBy == Self.date("2029-01-01"))
        #expect(result.flags == [.estimatedDate])
    }

    // MARK: The flag on Lot

    @Test func settingAPrintedDateClearsTheFlag() {
        var lot = Self.lot(noPrintedDate: true)
        lot.printedDate = Self.date("2027-01-01")
        #expect(!lot.noPrintedDate)
        #expect(lot.printedDate == Self.date("2027-01-01"))
    }

    @Test func tickingTheFlagClearsThePrintedDate() {
        var lot = Self.lot(printed: "2027-01-01")
        lot.noPrintedDate = true
        #expect(lot.printedDate == nil)
        #expect(lot.noPrintedDate)
    }

    @Test func aPrintedDateWinsWhenBothAreGiven() {
        let lot = Self.lot(printed: "2027-01-01", noPrintedDate: true)
        #expect(lot.printedDate == Self.date("2027-01-01"))
        #expect(!lot.noPrintedDate)
    }

    @Test func aLotWithoutTheFlagDecodesWithItOff() throws {
        let lot = Self.lot(noPrintedDate: true)
        var object = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(lot)) as? [String: Any])
        #expect(object["noPrintedDate"] as? Bool == true)
        object["noPrintedDate"] = nil
        let decoded = try JSONDecoder().decode(Lot.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(!decoded.noPrintedDate)
        #expect(decoded.id == lot.id)
    }

    // MARK: The bundled table

    @Test func everyDatedProfileHasAnEstimate() {
        for profile in Self.table.profiles where profile.dateType != .none {
            #expect(profile.rotationMonths != nil, "\(profile.key)")
        }
    }

    @Test(arguments: [ShelfLifeDateType.bestBy, .useBy])
    func aDatedProfileWithoutAnEstimateIsRefused(dateType: ShelfLifeDateType) {
        let json = #"[{"key": "flour", "name": "Flour", "dateType": "\#(dateType.rawValue)", "extensionMonths": 6}]"#
        #expect(throws: ShelfLifeProfileTable.LoadError.missingRotationMonths("flour")) {
            try ShelfLifeProfileTable(jsonData: Data(json.utf8))
        }
    }

    @Test func aNoDateProfileNeedsNoEstimate() throws {
        let json = #"[{"key": "salt", "name": "Salt", "dateType": "none"}]"#
        #expect(try ShelfLifeProfileTable(jsonData: Data(json.utf8))["salt"] != nil)
    }

    // MARK: Focus next and Inventory

    struct World {
        let site = Site(name: "Home")
        let pantry: Location
        var products: [Product] = []
        var lots: [Lot] = []

        init() { pantry = Location(siteID: site.id, name: "Pantry", climateClass: .climateControlled) }

        @discardableResult
        mutating func add(_ name: String, kcal: Double? = 300, printed: String? = nil, noPrintedDate: Bool = false) -> Lot {
            let product = Product(
                name: name, category: .food, role: .supply, unitKind: .count, kcalPerBaseUnit: kcal,
                shelfLifeProfileKey: "canned_low_acid")
            products.append(product)
            let lot = Lot(productID: product.id, quantity: 100, acquiredDate: date("2026-01-01"),
                          printedDate: printed.map(date), noPrintedDate: noPrintedDate, locationID: pantry.id)
            lots.append(lot)
            return lot
        }

        var inputs: RunwayInputs {
            RunwayInputs(site: site, occupants: [Person(siteID: site.id, name: "A")], lots: lots, products: products,
                         locations: [pantry], kits: [])
        }

        func statuses(on today: String = "2026-10-06") -> [LotStatus] {
            LotStatusEvaluator.statuses(for: inputs, profiles: table, on: date(today))
        }

        func focus(on today: String = "2026-10-06") -> [FocusItem] {
            FocusNext.items(
                runway: RunwayCalculator.runway(for: inputs, profiles: table, on: date(today)), statuses: statuses(on: today))
        }
    }

    @Test func focusNextListsMissingDateLotsLast() throws {
        var world = World()
        let zucchini = world.add("Zucchini")
        let apples = world.add("Apples")
        world.add("Dated", printed: "2027-06-01")
        world.add("Estimated", noPrintedDate: true)
        world.add("No calories", kcal: nil, printed: "2027-06-01")
        let items = world.focus()
        let last = try #require(items.last)
        #expect(last == .missingDate(lots: [apples.id, zucchini.id]))
        #expect(items.dropLast().last.map { if case .missingNutrition = $0 { true } else { false } } == true)
    }

    @Test func noMissingDateItemWhenEveryLotIsDated() {
        var world = World()
        world.add("Dated", printed: "2027-06-01")
        world.add("Estimated", noPrintedDate: true)
        #expect(!world.focus().contains { if case .missingDate = $0 { true } else { false } })
    }

    @Test func needsADateFilter() {
        var world = World()
        let missing = world.add("Missing")
        world.add("Dated", printed: "2027-06-01")
        world.add("Estimated", noPrintedDate: true)
        let statuses = world.statuses()
        let ids = Inventory.sections(statuses, locations: [world.pantry], query: InventoryQuery(needsDate: true))
            .flatMap(\.lots).map(\.id)
        #expect(ids == [missing.id])
        #expect(Inventory.sections(statuses, locations: [world.pantry], query: InventoryQuery()).flatMap(\.lots).count == 3)
    }
}
