import Foundation

/// Storage climate, which scales a shelf-life extension window.
public enum ClimateClass: String, Hashable, Sendable, Codable, CaseIterable {
    case coolDry
    case rootCellar
    case climateControlled
    case insulatedUnconditioned
    case hot
    case vehicle
    case refrigerated
    case frozen

    /// The class used when neither the lot nor any location in its chain sets one.
    public static let fallback: ClimateClass = .climateControlled

    /// Default window multiplier from the spec's climate table; editable per location later.
    /// `nil` for refrigerated and frozen, which are set per product.
    public var defaultWindowMultiplier: Double? {
        switch self {
        case .coolDry: 1.25
        case .rootCellar: 1.25
        case .climateControlled: 1.0
        case .insulatedUnconditioned: 0.75
        case .hot: 0.5
        case .vehicle: 0.33
        case .refrigerated, .frozen: nil
        }
    }
}

/// Humidity affects packaging (cans, cardboard, paper), not temperature.
public enum Humidity: String, Hashable, Sendable, Codable, CaseIterable {
    case dry
    case humid
}

/// Where a lot lives. Locations nest; a child without a climate class inherits its parent's.
public struct Location: Hashable, Sendable, Codable, Identifiable {
    public let id: LocationID
    public var siteID: SiteID
    public var name: String
    public var parentID: LocationID?
    public var climateClass: ClimateClass?
    public var humidity: Humidity?
    /// Set when this location is a kit (a go-bag, a car kit).
    public var kitID: KitID?

    public init(
        id: LocationID = LocationID(),
        siteID: SiteID,
        name: String,
        parentID: LocationID? = nil,
        climateClass: ClimateClass? = nil,
        humidity: Humidity? = nil,
        kitID: KitID? = nil
    ) {
        self.id = id
        self.siteID = siteID
        self.name = name
        self.parentID = parentID
        self.climateClass = climateClass
        self.humidity = humidity
        self.kitID = kitID
    }
}
