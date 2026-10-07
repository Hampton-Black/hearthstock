import Foundation
import GRDB
import HearthstockCore

struct LocationRecord: StoredRecord, Equatable {
    static let databaseTableName = "location"

    var id: String
    var siteId: String
    var parentId: String?
    var name: String
    var climateClass: String?
    var climateMultiplierOverride: Double?
    var humidity: String?
    /// Checked at commit (deferred), because the kit row references this location back.
    var kitId: String?
    var createdAt: Date?
    var updatedAt: Date?

    init(_ location: Location) {
        id = location.id.stored
        siteId = location.siteID.stored
        parentId = location.parentID?.stored
        name = location.name
        climateClass = location.climateClass?.rawValue
        climateMultiplierOverride = location.climateMultiplierOverride
        humidity = location.humidity?.rawValue
        kitId = location.kitID?.stored
    }

    func toCore() throws -> Location {
        let decoder = ColumnDecoder(table: Self.databaseTableName)
        return Location(
            id: try decoder.id("id", id),
            siteID: try decoder.id("siteId", siteId),
            name: name,
            parentID: try decoder.optionalID("parentId", parentId),
            climateClass: try decoder.optionalEnum("climateClass", climateClass),
            climateMultiplierOverride: climateMultiplierOverride,
            humidity: try decoder.optionalEnum("humidity", humidity),
            kitID: try decoder.optionalID("kitId", kitId)
        )
    }
}
