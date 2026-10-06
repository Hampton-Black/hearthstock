import Foundation

/// An independent place with its own runway (Main house, Bug-out cabin).
public struct Site: Hashable, Sendable, Codable, Identifiable {
    public let id: SiteID
    public var name: String

    public init(id: SiteID = SiteID(), name: String) {
        self.id = id
        self.name = name
    }
}

/// An occupant of a site, with daily calorie and water needs.
public struct Person: Hashable, Sendable, Codable, Identifiable {
    public static let defaultKcalPerDay: Double = 2000
    public static let defaultWaterGalPerDay: Double = 1.0

    public let id: PersonID
    public var siteID: SiteID
    public var name: String
    public var kcalPerDay: Double
    public var waterGalPerDay: Double

    public init(
        id: PersonID = PersonID(),
        siteID: SiteID,
        name: String,
        kcalPerDay: Double = Person.defaultKcalPerDay,
        waterGalPerDay: Double = Person.defaultWaterGalPerDay
    ) {
        self.id = id
        self.siteID = siteID
        self.name = name
        self.kcalPerDay = kcalPerDay
        self.waterGalPerDay = waterGalPerDay
    }
}
