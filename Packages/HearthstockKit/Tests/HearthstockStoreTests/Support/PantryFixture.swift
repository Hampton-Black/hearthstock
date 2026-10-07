import Foundation
import HearthstockCore
@testable import HearthstockStore

/// `Fixtures/sample-pantry.json`, shared with HearthstockCoreTests: one site's world plus the hand-computed
/// results. Mirrors the decoder in `RunwayCalculatorTests`.
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

extension PantryFixture {
    /// The fixture lives with HearthstockCoreTests and is read from the source tree, so there is one copy.
    /// SwiftPM can't share one resource folder between test targets, and these tests run on the Mac.
    private static let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "HearthstockCoreTests/Fixtures/sample-pantry.json", directoryHint: .notDirectory)

    static func load() throws -> PantryFixture {
        try JSONDecoder().decode(PantryFixture.self, from: Data(contentsOf: url))
    }

    /// Everything goes in through the repository protocols, parents before children.
    func populate(_ db: AppDatabase, clock: StoreClock = .system) async throws {
        let siteRepo = GRDBSiteRepository(database: db, clock: clock)
        let personRepo = GRDBPersonRepository(database: db, clock: clock)
        let locationRepo = GRDBLocationRepository(database: db, clock: clock)
        let productRepo = GRDBProductRepository(database: db, clock: clock)
        let lotRepo = GRDBLotRepository(database: db, clock: clock)
        let kitRepo = GRDBKitRepository(database: db, clock: clock)

        try await siteRepo.save(site)
        for person in occupants { try await personRepo.save(person) }
        for product in products { try await productRepo.save(product) }
        // A location and its kit refer to each other. Locations go in without their kit link; saving the
        // kit sets it, as the app does.
        for location in Self.parentsFirst(locations) {
            var unlinked = location
            unlinked.kitID = nil
            try await locationRepo.save(unlinked)
        }
        for kit in kits { try await kitRepo.save(kit) }
        for lot in lots { try await lotRepo.save(lot) }
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
}
