import Foundation

/// A location tied to a template. Its contents are ordinary lots in that location.
public struct Kit: Hashable, Sendable, Codable, Identifiable {
    public let id: KitID
    public var locationID: LocationID
    public var templateID: KitTemplateID?
    /// Off by default: go-bags and vehicle kits are meant to leave with you.
    public var countsTowardSiteRunway: Bool
    public var lastInspectedDate: CalendarDate?

    public init(
        id: KitID = KitID(),
        locationID: LocationID,
        templateID: KitTemplateID? = nil,
        countsTowardSiteRunway: Bool = false,
        lastInspectedDate: CalendarDate? = nil
    ) {
        self.id = id
        self.locationID = locationID
        self.templateID = templateID
        self.countsTowardSiteRunway = countsTowardSiteRunway
        self.lastInspectedDate = lastInspectedDate
    }
}
