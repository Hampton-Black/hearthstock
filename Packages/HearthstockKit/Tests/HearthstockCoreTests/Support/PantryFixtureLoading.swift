import Foundation
@testable import HearthstockCore

extension PantryFixture {
    static func load() throws -> PantryFixture {
        guard let url = Bundle.module.url(forResource: "sample-pantry", withExtension: "json", subdirectory: "Fixtures")
        else { throw CocoaError(.fileNoSuchFile) }
        return try JSONDecoder().decode(PantryFixture.self, from: Data(contentsOf: url))
    }

    /// The fixture's lot with this ID suffix ("…-000000000002" → 2).
    func lot(_ number: Int) -> Lot {
        lots.first { $0.id.rawValue.uuidString.hasSuffix(String(format: "%012d", number)) }!
    }

    func statuses(profiles: ShelfLifeProfileTable, on today: CalendarDate? = nil) -> [LotStatus] {
        LotStatusEvaluator.statuses(
            for: site, lots: lots, products: products, locations: locations, kits: kits,
            profiles: profiles, on: today ?? self.today)
    }

    func inputs() -> RunwayInputs {
        RunwayInputs(
            site: site, occupants: occupants, lots: lots.filter { !$0.archived }, products: products,
            locations: locations, kits: kits)
    }
}

func date(_ iso: String) -> CalendarDate { CalendarDate(iso: iso)! }
