import Foundation

public enum ClimateResolutionError: Error, Hashable, Sendable {
    /// The parent chain loops back on itself; `at` is the first location seen twice.
    case cycle(at: LocationID)
    /// A location or parent ID isn't in the lookup.
    case missingLocation(LocationID)
}

/// The climate a lot is stored in: its override, else its location chain.
public func resolvedClimate(
    for lot: Lot,
    locations: [LocationID: Location]
) throws(ClimateResolutionError) -> ClimateClass {
    if let override = lot.climateOverride { return override }
    return try resolvedClimate(of: lot.locationID, locations: locations)
}

/// The climate of a location: its own class, else the nearest ancestor's, else `ClimateClass.fallback`.
/// Stops at the first location that sets a class, so a cycle above it is never walked.
public func resolvedClimate(
    of locationID: LocationID,
    locations: [LocationID: Location]
) throws(ClimateResolutionError) -> ClimateClass {
    var visited: Set<LocationID> = []
    var current: LocationID? = locationID
    while let id = current {
        guard visited.insert(id).inserted else { throw .cycle(at: id) }
        guard let location = locations[id] else { throw .missingLocation(id) }
        if let climate = location.climateClass { return climate }
        current = location.parentID
    }
    return .fallback
}

/// The climate a lot is evaluated under: a class, and a window multiplier when a location overrides the class's.
struct StorageClimate: Hashable, Sendable {
    var climateClass: ClimateClass
    /// Nil uses the class's default multiplier.
    var windowMultiplier: Double?

    /// The lot's own class wins outright. Otherwise the class is the nearest one in `chain` (the lot's location and
    /// its ancestors, nearest first), and the multiplier override is the nearest location that sets a class or an
    /// override, if that one sets an override. So a child's own class shadows its parent's override, and an
    /// override on a location with no class sits on top of the inherited class.
    init(lot: Lot, chain: [Location]) {
        if let override = lot.climateOverride {
            self.init(climateClass: override, windowMultiplier: nil)
            return
        }
        let climateClass = chain.lazy.compactMap(\.climateClass).first ?? .fallback
        let setter = chain.first { $0.climateClass != nil || $0.climateMultiplierOverride != nil }
        self.init(climateClass: climateClass, windowMultiplier: setter?.climateMultiplierOverride)
    }

    init(climateClass: ClimateClass, windowMultiplier: Double?) {
        self.climateClass = climateClass
        self.windowMultiplier = windowMultiplier
    }
}
