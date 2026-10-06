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
            packaging: try decoder.enum("packaging", packaging),
            locationID: try decoder.id("locationId", locationId),
            climateOverride: try decoder.optionalEnum("climateOverride", climateOverride),
            notes: notes,
            opened: opened,
            archived: archived
        )
    }
}
