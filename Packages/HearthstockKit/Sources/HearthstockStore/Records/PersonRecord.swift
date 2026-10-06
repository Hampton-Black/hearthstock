import Foundation
import GRDB
import HearthstockCore

struct PersonRecord: StoredRecord, Equatable {
    static let databaseTableName = "person"

    var id: String
    var siteId: String
    var name: String
    var kcalPerDay: Double
    var waterGalPerDay: Double
    var createdAt: Date?
    var updatedAt: Date?

    init(_ person: Person) {
        id = person.id.stored
        siteId = person.siteID.stored
        name = person.name
        kcalPerDay = person.kcalPerDay
        waterGalPerDay = person.waterGalPerDay
    }

    func toCore() throws -> Person {
        let decoder = ColumnDecoder(table: Self.databaseTableName)
        return Person(
            id: try decoder.id("id", id),
            siteID: try decoder.id("siteId", siteId),
            name: name,
            kcalPerDay: kcalPerDay,
            waterGalPerDay: waterGalPerDay
        )
    }
}
