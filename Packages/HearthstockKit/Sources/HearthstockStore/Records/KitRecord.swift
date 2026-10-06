import Foundation
import GRDB
import HearthstockCore

/// Core's `Kit` has no site; the row's `homeSiteId` is its location's site, so the caller supplies it
/// (the schema's triggers reject a mismatch).
struct KitRecord: StoredRecord, Equatable {
    static let databaseTableName = "kit"

    var id: String
    var homeSiteId: String
    var locationId: String
    var templateId: String?
    var countsTowardSiteRunway: Bool
    var lastInspected: String?
    var createdAt: Date?
    var updatedAt: Date?

    init(_ kit: Kit, homeSiteID: SiteID) {
        id = kit.id.stored
        homeSiteId = homeSiteID.stored
        locationId = kit.locationID.stored
        templateId = kit.templateID?.stored
        countsTowardSiteRunway = kit.countsTowardSiteRunway
        lastInspected = kit.lastInspectedDate?.iso
    }

    func toCore() throws -> Kit {
        let decoder = ColumnDecoder(table: Self.databaseTableName)
        return Kit(
            id: try decoder.id("id", id),
            locationID: try decoder.id("locationId", locationId),
            templateID: try decoder.optionalID("templateId", templateId),
            countsTowardSiteRunway: countsTowardSiteRunway,
            lastInspectedDate: try decoder.optionalDate("lastInspected", lastInspected)
        )
    }
}
