import Foundation
import Testing
@testable import HearthstockCore

@Suite struct ShelfLifeEvaluatorTests {
    static func date(_ iso: String) -> CalendarDate { CalendarDate(iso: iso)! }

    static func profile(_ key: String) -> ShelfLifeProfile {
        try! ShelfLifeProfileTable.bundledDefaults()[ShelfLifeProfileKey(rawValue: key)]!
    }

    static func lot(
        acquired: String = "2025-01-01",
        printed: String? = nil,
        packaging: Packaging = .none
    ) -> Lot {
        Lot(
            productID: ProductID(),
            quantity: 1,
            acquiredDate: date(acquired),
            printedDate: printed.map(date),
            packaging: packaging,
            locationID: LocationID()
        )
    }

    static func evaluate(
        _ lot: Lot,
        _ key: String,
        climate: ClimateClass = .climateControlled,
        humidity: Humidity = .dry,
        on today: String
    ) -> ShelfLifeEvaluation {
        ShelfLifeEvaluator.evaluate(lot, profile: profile(key), climate: climate, humidity: humidity, on: date(today))
    }

    // MARK: Best-by boundaries

    /// Low-acid can printed 2026-01-01, climate controlled: 730-day window, last 146 days are Inspect.
    @Test(arguments: [
        ("2025-06-01", LotState.good),
        ("2026-01-01", .good),  // exactly on the printed date
        ("2026-01-02", .caution),  // first caution day
        ("2027-08-08", .caution),  // last caution day
        ("2027-08-09", .inspect),  // first inspect day
        ("2028-01-01", .inspect),  // usable-by, last usable day
        ("2028-01-02", .expired),  // first expired day
    ])
    func bestByBoundaries(today: String, expected: LotState) {
        let result = Self.evaluate(Self.lot(printed: "2026-01-01"), "canned_low_acid", on: today)
        #expect(result.state == expected)
        #expect(result.usableBy == Self.date("2028-01-01"))
        #expect(result.flags.isEmpty)
    }

    @Test(arguments: [
        (ClimateClass.hot, "2027-01-01"),  // 730 × 0.5 = 365 days
        (.climateControlled, "2028-01-01"),  // 730 days
        (.coolDry, "2028-07-01"),  // 730 × 1.25 = 912.5 → 912 days
        (.vehicle, "2026-08-29"),  // 730 × 0.33 = 240.9 → 240 days
    ])
    func climateScalesTheWindow(climate: ClimateClass, usableBy: String) {
        let result = Self.evaluate(
            Self.lot(printed: "2026-01-01"), "canned_low_acid", climate: climate, on: "2026-06-01")
        #expect(result.usableBy == Self.date(usableBy))
    }

    @Test func hotGarageVersusCoolDryForTheSameCan() {
        let can = Self.lot(printed: "2026-01-01")
        let today = "2027-03-01"
        #expect(Self.evaluate(can, "canned_low_acid", climate: .hot, on: today).state == .expired)
        #expect(Self.evaluate(can, "canned_low_acid", climate: .coolDry, on: today).state == .caution)
    }

    @Test func bestByWithZeroWindowExpiresTheDayAfter() {
        let profile = ShelfLifeProfile(key: "zero", dateType: .bestBy, extensionMonths: 0)
        let lot = Self.lot(printed: "2026-03-10")
        func state(_ today: String) -> LotState {
            ShelfLifeEvaluator.evaluate(lot, profile: profile, climate: .coolDry, on: Self.date(today)).state
        }
        #expect(state("2026-03-10") == .good)
        #expect(state("2026-03-11") == .expired)
    }

    // MARK: Use-by

    @Test(arguments: [
        ("2026-10-05", LotState.good),
        ("2026-10-06", .expired),
    ])
    func useByHasNoExtension(today: String, expected: LotState) {
        let formula = Self.lot(printed: "2026-10-05")
        let result = Self.evaluate(formula, "infant_formula", on: today)
        #expect(result.state == expected)
        #expect(result.usableBy == Self.date("2026-10-05"))
    }

    @Test func useByIgnoresClimateAndPackaging() {
        let lot = Self.lot(printed: "2026-10-05", packaging: .bucket)
        for climate in [ClimateClass.coolDry, .hot, .vehicle] {
            let result = Self.evaluate(lot, "medication", climate: climate, on: "2026-10-05")
            #expect(result.usableBy == Self.date("2026-10-05"))
            #expect(result.state == .good)
        }
    }

    // MARK: Packaging

    @Test func mylarRiceWithAnOldPrintedDateIsStillGood() {
        let rice = Self.lot(acquired: "2024-01-01", printed: "2020-01-01", packaging: .mylarO2)
        let result = Self.evaluate(rice, "white_rice", on: "2026-10-06")
        #expect(result.state == .good)
        #expect(result.usableBy == Self.date("2034-01-01"))  // acquired + 120 months
    }

    @Test func packagedLifeIsClimateScaled() {
        // 2024-01-01 → 2034-01-01 is 3,653 days; × 0.5 = 1,826.5 → 1,826 days.
        let rice = Self.lot(acquired: "2024-01-01", packaging: .bucket)
        let result = Self.evaluate(rice, "white_rice", climate: .hot, on: "2026-10-06")
        #expect(result.usableBy == Self.date("2028-12-31"))
        #expect(result.state == .good)
    }

    @Test func laterOfPrintedAndPackagedRuleWins() {
        // Printed rule: 2030-01-01 + 12 months = 2031-01-01. Packaged: 2024-01-01 + 60 months = 2029-01-01.
        let oats = Self.lot(acquired: "2024-01-01", printed: "2030-01-01", packaging: .mylarO2)
        let result = Self.evaluate(oats, "rolled_oats", on: "2031-06-01")
        #expect(result.usableBy == Self.date("2031-01-01"))
        #expect(result.state == .expired)

        let rice = Self.lot(acquired: "2024-01-01", printed: "2030-01-01", packaging: .mylarO2)
        let riceResult = Self.evaluate(rice, "white_rice", on: "2031-06-01")
        #expect(riceResult.usableBy == Self.date("2034-01-01"))
        #expect(riceResult.state == .good)
    }

    @Test(arguments: [
        ("2032-01-01", LotState.good),
        ("2032-01-02", .inspect),  // last 20% of 3,653 days = 731 days
        ("2034-01-01", .inspect),
        ("2034-01-02", .expired),
    ])
    func packagedRuleHasNoCautionBand(today: String, expected: LotState) {
        let rice = Self.lot(acquired: "2024-01-01", packaging: .mylarO2)
        #expect(Self.evaluate(rice, "white_rice", on: today).state == expected)
    }

    @Test func packagingWithoutAPackagedLifeFallsBackToPrintedDate() {
        let can = Self.lot(printed: "2026-01-01", packaging: .bucket)
        #expect(Self.evaluate(can, "canned_low_acid", on: "2026-06-01").usableBy == Self.date("2028-01-01"))
    }

    @Test func stabilizedPackagingDoesNotUsePackagedLife() {
        let rice = Self.lot(acquired: "2024-01-01", printed: "2020-01-01", packaging: .stabilized)
        #expect(Self.evaluate(rice, "white_rice", on: "2026-10-06").state == .expired)
    }

    // MARK: Rotation (no printed date)

    @Test(arguments: [
        ("2025-01-01", LotState.good),
        ("2025-05-25", .good),  // last good day: 181-day window, last 37 days are Inspect
        ("2025-05-26", .inspect),
        ("2025-06-01", .inspect),  // 5 months
        ("2025-07-01", .inspect),  // usable-by
        ("2025-07-02", .expired),
        ("2025-08-01", .expired),  // 7 months
    ])
    func storedTapWaterRotation(today: String, expected: LotState) {
        let water = Self.lot(acquired: "2025-01-01")
        let result = Self.evaluate(water, "stored_tap_water", on: today)
        #expect(result.state == expected)
        #expect(result.usableBy == Self.date("2025-07-01"))
    }

    @Test func rotationIsNotClimateScaled() {
        let water = Self.lot(acquired: "2025-01-01")
        for climate in [ClimateClass.coolDry, .hot, .vehicle] {
            #expect(Self.evaluate(water, "stored_tap_water", climate: climate, on: "2025-03-01").usableBy
                == Self.date("2025-07-01"))
        }
    }

    // MARK: No date

    @Test func neverExpiringProfileIsAlwaysGood() {
        let honey = Self.lot(acquired: "1990-01-01")
        let result = Self.evaluate(honey, "honey_salt_sugar", climate: .hot, on: "2026-10-06")
        #expect(result.state == .good)
        #expect(result.usableBy == nil)
        #expect(result.flags.isEmpty)
    }

    @Test func missingPrintedDateIsGoodAndFlagged() {
        let can = Self.lot(acquired: "2010-01-01")
        let result = Self.evaluate(can, "canned_low_acid", on: "2026-10-06")
        #expect(result.state == .good)
        #expect(result.usableBy == nil)
        #expect(result.flags == [.missingDate])
    }

    @Test func missingPrintedDateOnUseByIsFlagged() {
        let result = Self.evaluate(Self.lot(), "medication", on: "2026-10-06")
        #expect(result.state == .good)
        #expect(result.flags == [.missingDate])
    }

    @Test func packagedLotWithoutPrintedDateIsNotFlagged() {
        let rice = Self.lot(acquired: "2024-01-01", packaging: .mylarO2)
        #expect(Self.evaluate(rice, "white_rice", on: "2026-10-06").flags.isEmpty)
    }

    // MARK: Refrigerated / frozen

    @Test(arguments: [ClimateClass.refrigerated, .frozen])
    func coldStorageEvaluatesAsClimateControlledAndIsPowerDependent(climate: ClimateClass) {
        let result = Self.evaluate(Self.lot(printed: "2026-01-01"), "canned_low_acid", climate: climate, on: "2026-06-01")
        #expect(result.usableBy == Self.date("2028-01-01"))
        #expect(result.flags == [.powerDependent])
    }

    // MARK: Humidity

    @Test(arguments: Packaging.allCases)
    func humidityFlagsOnlyUnsealedPackaging(packaging: Packaging) {
        let can = Self.lot(printed: "2026-01-01", packaging: packaging)
        let humid = Self.evaluate(can, "canned_low_acid", humidity: .humid, on: "2026-06-01")
        let dry = Self.evaluate(can, "canned_low_acid", humidity: .dry, on: "2026-06-01")
        #expect(humid.flags.contains(.humidityRisk) == (packaging == .none))
        #expect(!dry.flags.contains(.humidityRisk))
        #expect(humid.usableBy == dry.usableBy)
        #expect(humid.state == dry.state)
    }

    // MARK: Window multiplier override

    @Test func windowMultiplierReplacesTheClimateClassMultiplier() {
        // canned_low_acid printed 2026-01-01, 730 days: ×0.5 → usable through 2027-01-01, exactly like `.hot`.
        let lot = Self.lot(printed: "2026-01-01")
        let overridden = ShelfLifeEvaluator.evaluate(
            lot, profile: Self.profile("canned_low_acid"), climate: .climateControlled, windowMultiplier: 0.5,
            on: Self.date("2026-06-01"))
        let hot = Self.evaluate(lot, "canned_low_acid", climate: .hot, on: "2026-06-01")
        #expect(overridden == hot)
        #expect(overridden.usableBy == Self.date("2027-01-01"))
    }

    @Test func nilWindowMultiplierKeepsTheClassMultiplier() {
        let lot = Self.lot(printed: "2026-01-01")
        let result = ShelfLifeEvaluator.evaluate(
            lot, profile: Self.profile("canned_low_acid"), climate: .hot, windowMultiplier: nil,
            on: Self.date("2026-06-01"))
        #expect(result == Self.evaluate(lot, "canned_low_acid", climate: .hot, on: "2026-06-01"))
    }

    /// 730 days × 0.5 = 365 → usable through 2027-01-01; 730 × 0.49 = 357.7 → 357 days → through 2026-12-24.
    @Test(arguments: [
        (0.5, "2027-01-01", LotState.inspect),  // last usable day under ×0.5
        (0.5, "2027-01-02", .expired),
        (0.49, "2026-12-24", .inspect),  // the nudge moves the boundary a week earlier
        (0.49, "2026-12-25", .expired),
    ])
    func multiplierMovesTheBoundaryDay(multiplier: Double, today: String, expected: LotState) {
        let result = ShelfLifeEvaluator.evaluate(
            Self.lot(printed: "2026-01-01"), profile: Self.profile("canned_low_acid"), climate: .climateControlled,
            windowMultiplier: multiplier, on: Self.date(today))
        #expect(result.state == expected)
    }

    @Test func windowMultiplierOnColdStorageStillFlagsPowerDependent() {
        let result = ShelfLifeEvaluator.evaluate(
            Self.lot(printed: "2026-01-01"), profile: Self.profile("canned_low_acid"), climate: .refrigerated,
            windowMultiplier: 0.5, on: Self.date("2026-06-01"))
        #expect(result.usableBy == Self.date("2027-01-01"))
        #expect(result.flags == [.powerDependent])
    }

    @Test func windowMultiplierDoesNotScaleRotationWindows() {
        // Rotation months run from the acquired date unscaled, as without an override.
        let lot = Self.lot(acquired: "2026-01-01")
        let result = ShelfLifeEvaluator.evaluate(
            lot, profile: Self.profile("stored_tap_water"), climate: .climateControlled, windowMultiplier: 0.5,
            on: Self.date("2026-06-01"))
        #expect(result.usableBy == Self.date("2026-07-01"))
    }
}
