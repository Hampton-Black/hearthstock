#if DEBUG
import Foundation
import HearthstockCore

/// Development only: puts the Slice 1 sample pantry (`sample-pantry.json`, the same file the tests use) into
/// the current site so the simulator has something to show. Everything goes in through the repository
/// protocols, re-homed to the given site.
struct SamplePantry: Decodable {
    var occupants: [Person]
    var locations: [Location]
    var kits: [Kit]
    var products: [Product]
    var lots: [Lot]

    enum LoadError: Error, LocalizedError {
        case missingResource
        case siteNotEmpty

        var errorDescription: String? {
            switch self {
            case .missingResource: "sample-pantry.json isn't in the app bundle"
            case .siteNotEmpty: "The site already has data; sample pantry only loads into an empty one"
            }
        }
    }

    static func load(into services: AppServices, siteID: SiteID) async throws {
        guard let url = Bundle.main.url(forResource: "sample-pantry", withExtension: "json") else {
            throw LoadError.missingResource
        }
        let pantry = try JSONDecoder().decode(SamplePantry.self, from: Data(contentsOf: url))

        let existing = try await services.runwayInputs.load(siteID: siteID)
        guard existing.lots.isEmpty, existing.locations.isEmpty, existing.occupants.isEmpty else {
            throw LoadError.siteNotEmpty
        }

        for product in pantry.products { try await services.products.save(product) }
        for var person in pantry.occupants {
            person.siteID = siteID
            try await services.people.save(person)
        }
        // A location and its kit refer to each other: locations go in without their kit link, and saving
        // the kit sets it.
        for var location in parentsFirst(pantry.locations) {
            location.siteID = siteID
            location.kitID = nil
            try await services.locations.save(location)
        }
        for kit in pantry.kits { try await services.kits.save(kit) }
        for lot in pantry.lots { try await services.lots.save(lot) }
    }

    private static func parentsFirst(_ locations: [Location]) -> [Location] {
        var ordered: [Location] = []
        var remaining = locations
        var placed: Set<LocationID> = []
        while !remaining.isEmpty {
            let ready = remaining.filter { $0.parentID.map(placed.contains) ?? true }
            // A cycle or missing parent in the fixture: place the rest as they are and let the store refuse.
            guard !ready.isEmpty else { return ordered + remaining }
            ordered += ready
            placed.formUnion(ready.map(\.id))
            remaining.removeAll { placed.contains($0.id) }
        }
        return ordered
    }
}
#endif
