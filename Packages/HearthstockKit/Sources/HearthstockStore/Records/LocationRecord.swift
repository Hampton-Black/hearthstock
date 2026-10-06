import Foundation
import GRDB
import HearthstockCore

/// `location.climateMultiplierOverride` has no Core counterpart yet, so this record leaves it out:
/// inserts store NULL and updates never touch it. The shelf-life and climate overrides task owns it.
struct LocationRecord: StoredRecord, Equatable {
    static let databaseTableName = "location"

    var id: String
    var siteId: String
    var parentId: String?
    var name: String
    var climateClass: String?
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
            humidity: try decoder.optionalEnum("humidity", humidity),
            kitID: try decoder.optionalID("kitId", kitId)
        )
    }
}
