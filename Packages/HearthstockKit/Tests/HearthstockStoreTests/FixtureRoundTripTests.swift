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

    /// The fixture lives with HearthstockCoreTests and is read from the source tree, so there is one copy.
    /// SwiftPM can't share one resource folder between test targets, and these tests run on the Mac.
    private static let fixtureURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "HearthstockCoreTests/Fixtures/sample-pantry.json", directoryHint: .notDirectory)

    init() async throws {
        fixture = try JSONDecoder().decode(PantryFixture.self, from: Data(contentsOf: Self.fixtureURL))
        db = try AppDatabase.inMemory()
        loader = GRDBRunwayInputsLoader(database: db)
        try await populate()
    }

    /// Everything goes in through the repository protocols, parents before children.
    private func populate() async throws {
        let sites = GRDBSiteRepository(database: db)
        let people = GRDBPersonRepository(database: db)
        let locations = GRDBLocationRepository(database: db)
        let products = GRDBProductRepository(database: db)
        let lots = GRDBLotRepository(database: db)
        let kits = GRDBKitRepository(database: db)

        try await sites.save(fixture.site)
        for person in fixture.occupants { try await people.save(person) }
        for product in fixture.products { try await products.save(product) }
        // A location and its kit refer to each other. Locations go in without their kit link; saving the
        // kit sets it, as the app does.
        for location in Self.parentsFirst(fixture.locations) {
            var unlinked = location
            unlinked.kitID = nil
            try await locations.save(unlinked)
        }
        for kit in fixture.kits { try await kits.save(kit) }
        for lot in fixture.lots { try await lots.save(lot) }
    }

    private static func parentsFirst(_ locations: [Location]) -> [Location] {
        var ordered: [Location] = []
        var remaining = locations
        var placed: Set<LocationID> = []
        while !remaining.isEmpty {
            let ready = remaining.filter { $0.parentID.map(placed.contains) ?? true }
            precondition(!ready.isEmpty, "fixture locations contain a cycle or a missing parent")
            ordered += ready
            placed.formUnion(ready.map(\.id))
            remaining.removeAll { placed.contains($0.id) }
        }
        return ordered
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

/// `Fixtures/sample-pantry.json`, shared with HearthstockCoreTests: one site's world plus the hand-computed
/// results. Mirrors the decoder in `RunwayCalculatorTests`.
private struct PantryFixture: Decodable {
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
