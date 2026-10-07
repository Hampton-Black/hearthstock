import Foundation
import HearthstockCore
import Testing
@testable import HearthstockStore

/// The main regression test for persistence: the Slice 1 sample pantry goes into an in-memory database through
/// the repositories, comes back through the runway-inputs loader, and must produce the same runway the
/// calculator produces for the fixture directly. The database adds nothing and loses nothing. Keep this green
/// in every slice.
@Suite struct FixtureRoundTripTests {
    private let fixture: PantryFixture
    private let db: AppDatabase
    private let loader: GRDBRunwayInputsLoader

    init() async throws {
        fixture = try PantryFixture.load()
        db = try AppDatabase.inMemory()
        loader = GRDBRunwayInputsLoader(database: db)
        try await fixture.populate(db)
    }

    @Test func loadedInputsMatchTheFixture() async throws {
        let inputs = try await loader.load(siteID: fixture.site.id)

        #expect(inputs.site == fixture.site)
        #expect(Set(inputs.occupants) == Set(fixture.occupants))
        #expect(Set(inputs.products) == Set(fixture.products))
        #expect(Set(inputs.locations) == Set(fixture.locations))
        #expect(Set(inputs.kits) == Set(fixture.kits))
        #expect(inputs.lots.count == fixture.lots.filter { !$0.archived }.count)
        #expect(Set(inputs.lots) == Set(fixture.lots.filter { !$0.archived }))
        #expect(inputs.productShelfLifeOverrides.isEmpty)
        #expect(inputs.lotShelfLifeOverrides.isEmpty)
    }

    @Test func archivedLotsStayInTheDatabaseButOutOfRunwayInputs() async throws {
        let archived = fixture.lots.filter(\.archived)
        try #require(!archived.isEmpty)

        let all = try await GRDBLotRepository(database: db).list(siteID: fixture.site.id, includeArchived: true)
        #expect(Set(all) == Set(fixture.lots))
    }

    @Test func runwayFromTheDatabaseMatchesTheSlice1Expectations() async throws {
        let expected = fixture.expected
        let profiles = try ShelfLifeProfileTable.bundledDefaults()
        let inputs = try await loader.load(siteID: fixture.site.id)

        let runway = RunwayCalculator.runway(for: inputs, profiles: profiles, on: fixture.today)

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
