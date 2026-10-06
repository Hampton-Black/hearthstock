import Foundation
import GRDB
import HearthstockCore

struct SiteRecord: StoredRecord, Equatable {
    static let databaseTableName = "site"

    var id: String
    var name: String
    var createdAt: Date?
    var updatedAt: Date?

    init(_ site: Site) {
        id = site.id.stored
        name = site.name
    }

    func toCore() throws -> Site {
        let decoder = ColumnDecoder(table: Self.databaseTableName)
        return Site(id: try decoder.id("id", id), name: name)
    }
}
