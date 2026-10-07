import Foundation
import GRDB
import HearthstockCore

struct SiteRecord: StoredRecord, Equatable {
    static let databaseTableName = "site"

    var id: String
    var name: String
    /// Added in `v2_site_notice_window` and backup format 2.
    var noticeWindowDays: Int
    var createdAt: Date?
    var updatedAt: Date?

    init(_ site: Site) {
        id = site.id.stored
        name = site.name
        noticeWindowDays = site.noticeWindowDays
    }

    /// A version 1 backup has no `noticeWindowDays`; its sites get the default, as the migration gave them.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        noticeWindowDays = try container.decodeIfPresent(Int.self, forKey: .noticeWindowDays)
            ?? Site.defaultNoticeWindowDays
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
    }

    func toCore() throws -> Site {
        let decoder = ColumnDecoder(table: Self.databaseTableName)
        return Site(id: try decoder.id("id", id), name: name, noticeWindowDays: noticeWindowDays)
    }
}
