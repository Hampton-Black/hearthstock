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
