import Foundation
import GRDB
import HearthstockCore

/// Core's `Lot` has no site; `siteId` is its location's site, so the caller supplies it
/// (the schema's triggers reject a mismatch).
struct LotRecord: StoredRecord, Equatable {
    static let databaseTableName = "lot"

    var id: String
    var siteId: String
    var productId: String
    var locationId: String
    var quantity: Double
    var acquiredDate: String
    var printedDate: String?
    /// Slice 4 (`v4_lot_no_printed_date`); absent from version 1 and 2 backups, where it reads as off.
    var noPrintedDate: Bool
    var packaging: String
    var climateOverride: String?
    var opened: Bool
    var archived: Bool
    var notes: String?
    var createdAt: Date?
    var updatedAt: Date?

    init(_ lot: Lot, siteID: SiteID) {
        id = lot.id.stored
        siteId = siteID.stored
        productId = lot.productID.stored
        locationId = lot.locationID.stored
        quantity = lot.quantity
        acquiredDate = lot.acquiredDate.iso
        printedDate = lot.printedDate?.iso
        noPrintedDate = lot.noPrintedDate
        packaging = lot.packaging.rawValue
        climateOverride = lot.climateOverride?.rawValue
        opened = lot.opened
        archived = lot.archived
        notes = lot.notes
    }

    func toCore() throws -> Lot {
        let decoder = ColumnDecoder(table: Self.databaseTableName)
        return Lot(
            id: try decoder.id("id", id),
            productID: try decoder.id("productId", productId),
            quantity: quantity,
            acquiredDate: try decoder.date("acquiredDate", acquiredDate),
            printedDate: try decoder.optionalDate("printedDate", printedDate),
            noPrintedDate: noPrintedDate,
            packaging: try decoder.enum("packaging", packaging),
            locationID: try decoder.id("locationId", locationId),
            climateOverride: try decoder.optionalEnum("climateOverride", climateOverride),
            notes: notes,
            opened: opened,
            archived: archived
        )
    }
}

extension LotRecord {
    private enum CodingKeys: String, CodingKey {
        case id, siteId, productId, locationId, quantity, acquiredDate, printedDate, noPrintedDate, packaging
        case climateOverride, opened, archived, notes, createdAt, updatedAt
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        siteId = try container.decode(String.self, forKey: .siteId)
        productId = try container.decode(String.self, forKey: .productId)
        locationId = try container.decode(String.self, forKey: .locationId)
        quantity = try container.decode(Double.self, forKey: .quantity)
        acquiredDate = try container.decode(String.self, forKey: .acquiredDate)
        printedDate = try container.decodeIfPresent(String.self, forKey: .printedDate)
        noPrintedDate = try container.decodeIfPresent(Bool.self, forKey: .noPrintedDate) ?? false
        packaging = try container.decode(String.self, forKey: .packaging)
        climateOverride = try container.decodeIfPresent(String.self, forKey: .climateOverride)
        opened = try container.decode(Bool.self, forKey: .opened)
        archived = try container.decode(Bool.self, forKey: .archived)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
    }
}
