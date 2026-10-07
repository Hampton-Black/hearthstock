import Foundation
import Testing
@testable import HearthstockCore

@Suite struct ShelfLifeProfileResolverTests {
    static let rice = Product(
        name: "Rice", category: .food, role: .supply, unitKind: .mass, kcalPerBaseUnit: 1600,
        shelfLifeProfileKey: "white_rice")
    static let table = try! ShelfLifeProfileTable.bundledDefaults()

    static func lot(of product: Product = rice) -> Lot {
        Lot(
            productID: product.id, quantity: 1, acquiredDate: CalendarDate(iso: "2025-01-01")!,
            locationID: LocationID())
    }

    /// white_rice ships as bestBy, 24 months extension, 120 months packaged life, no rotation.
    static var defaultProfile: ShelfLifeProfile { table["white_rice"]! }

    // MARK: Resolution order

    @Test func noOverridesResolvesTheBundledDefault() {
        let resolver = ShelfLifeProfileResolver(table: Self.table)
        #expect(resolver.profile(for: Self.lot(), product: Self.rice) == Self.defaultProfile)
    }

    @Test func productOverrideBeatsTheDefault() {
        let resolver = ShelfLifeProfileResolver(
            table: Self.table,
            productOverrides: [Self.rice.id: ShelfLifeOverride(extensionMonths: 6)])
        #expect(resolver.profile(for: Self.lot(), product: Self.rice)?.extensionMonths == 6)
    }

    @Test func lotOverrideBeatsTheProductOverride() {
        let lot = Self.lot()
        let resolver = ShelfLifeProfileResolver(
            table: Self.table,
            productOverrides: [Self.rice.id: ShelfLifeOverride(extensionMonths: 6)],
            lotOverrides: [lot.id: ShelfLifeOverride(extensionMonths: 1)])
        #expect(resolver.profile(for: lot, product: Self.rice)?.extensionMonths == 1)
    }

    @Test func lotOverrideAloneBeatsTheDefault() {
        let lot = Self.lot()
        let resolver = ShelfLifeProfileResolver(
            table: Self.table, lotOverrides: [lot.id: ShelfLifeOverride(extensionMonths: 1)])
        #expect(resolver.profile(for: lot, product: Self.rice)?.extensionMonths == 1)
    }

    @Test func overridesOnOtherProductsAndLotsAreIgnored() {
        let other = Product(
            name: "Beans", category: .food, role: .supply, unitKind: .mass, shelfLifeProfileKey: "dried_beans")
        let resolver = ShelfLifeProfileResolver(
            table: Self.table,
            productOverrides: [other.id: ShelfLifeOverride(extensionMonths: 1)],
            lotOverrides: [LotID(): ShelfLifeOverride(extensionMonths: 2)])
        #expect(resolver.profile(for: Self.lot(), product: Self.rice) == Self.defaultProfile)
    }

    // MARK: Partial overrides

    @Test func overridingOneFieldKeepsTheRestOfTheDefault() throws {
        let resolver = ShelfLifeProfileResolver(
            table: Self.table,
            productOverrides: [Self.rice.id: ShelfLifeOverride(extensionMonths: 6)])
        let profile = try #require(resolver.profile(for: Self.lot(), product: Self.rice))
        #expect(profile.key == "white_rice")
        #expect(profile.dateType == .bestBy)
        #expect(profile.extensionMonths == 6)
        #expect(profile.packagedLifeMonths == 120)
        #expect(profile.rotationMonths == nil)
    }

    @Test func eachFieldFallsBackIndependentlyAcrossLevels() throws {
        let lot = Self.lot()
        let resolver = ShelfLifeProfileResolver(
            table: Self.table,
            productOverrides: [
                Self.rice.id: ShelfLifeOverride(dateType: ShelfLifeDateType.none, extensionMonths: 6, rotationMonths: 18)
            ],
            lotOverrides: [lot.id: ShelfLifeOverride(extensionMonths: 1, packagedLifeMonths: 12)])
        let profile = try #require(resolver.profile(for: lot, product: Self.rice))
        #expect(profile.dateType == .none)  // product
        #expect(profile.extensionMonths == 1)  // lot beats product
        #expect(profile.packagedLifeMonths == 12)  // lot beats default
        #expect(profile.rotationMonths == 18)  // product beats default
    }

    @Test func zeroIsAValueNotAnAbsence() {
        let resolver = ShelfLifeProfileResolver(
            table: Self.table,
            productOverrides: [Self.rice.id: ShelfLifeOverride(extensionMonths: 0)])
        #expect(resolver.profile(for: Self.lot(), product: Self.rice)?.extensionMonths == 0)
    }

    @Test func emptyOverrideChangesNothing() {
        let lot = Self.lot()
        let resolver = ShelfLifeProfileResolver(
            table: Self.table,
            productOverrides: [Self.rice.id: ShelfLifeOverride()],
            lotOverrides: [lot.id: ShelfLifeOverride()])
        #expect(resolver.profile(for: lot, product: Self.rice) == Self.defaultProfile)
    }

    @Test func isEmptyReflectsEveryField() {
        #expect(ShelfLifeOverride().isEmpty)
        #expect(!ShelfLifeOverride(dateType: .useBy).isEmpty)
        #expect(!ShelfLifeOverride(extensionMonths: 0).isEmpty)
        #expect(!ShelfLifeOverride(packagedLifeMonths: 0).isEmpty)
        #expect(!ShelfLifeOverride(rotationMonths: 0).isEmpty)
    }

    // MARK: Missing default

    @Test func unknownKeyResolvesToNilEvenWithOverrides() {
        let ghost = Product(
            name: "Ghost", category: .food, role: .supply, unitKind: .count, shelfLifeProfileKey: "no_such_key")
        let lot = Self.lot(of: ghost)
        let resolver = ShelfLifeProfileResolver(
            table: Self.table,
            productOverrides: [ghost.id: ShelfLifeOverride(extensionMonths: 6)],
            lotOverrides: [lot.id: ShelfLifeOverride(extensionMonths: 1)])
        #expect(resolver.profile(for: lot, product: ghost) == nil)
    }

    // MARK: Effect on evaluation

    @Test func resolvedProfileDrivesTheEvaluatedState() {
        // Rice printed 2026-01-01; the 24-month default extension is usable through 2028-01-01.
        let lot = Lot(
            productID: Self.rice.id, quantity: 1, acquiredDate: CalendarDate(iso: "2025-01-01")!,
            printedDate: CalendarDate(iso: "2026-01-01")!, locationID: LocationID())
        let today = CalendarDate(iso: "2026-10-06")!
        func state(_ resolver: ShelfLifeProfileResolver) -> LotState {
            ShelfLifeEvaluator.evaluate(
                lot, profile: resolver.profile(for: lot, product: Self.rice)!, climate: .climateControlled, on: today
            ).state
        }
        #expect(state(ShelfLifeProfileResolver(table: Self.table)) == .caution)
        let shortened = ShelfLifeProfileResolver(
            table: Self.table, lotOverrides: [lot.id: ShelfLifeOverride(extensionMonths: 6)])
        #expect(state(shortened) == .expired)  // 6 months from 2026-01-01 ended 2026-07-01
    }
}
