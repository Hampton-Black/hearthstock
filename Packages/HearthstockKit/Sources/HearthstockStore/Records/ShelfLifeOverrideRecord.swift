import Foundation
import GRDB
import HearthstockCore

/// One row of `shelf_life_override`: edits to a profile for exactly one product or one lot (the schema's
/// CHECK and unique indexes enforce that). Core's `ShelfLifeOverride` carries neither the owner nor an ID,
/// so the caller supplies both.
struct ShelfLifeOverrideRecord: StoredRecord, Equatable {
    static let databaseTableName = "shelf_life_override"

    var id: String
    var productId: String?
    var lotId: String?
    var dateType: String?
    var extensionMonths: Int?
    var packagedLifeMonths: Int?
    var rotationMonths: Int?
    var createdAt: Date?
    var updatedAt: Date?

    init(_ override: ShelfLifeOverride, id: String = UUID().uuidString, productID: ProductID) {
        self.init(override, id: id, productId: productID.stored, lotId: nil)
    }

    init(_ override: ShelfLifeOverride, id: String = UUID().uuidString, lotID: LotID) {
        self.init(override, id: id, productId: nil, lotId: lotID.stored)
    }

    private init(_ override: ShelfLifeOverride, id: String, productId: String?, lotId: String?) {
        self.id = id
        self.productId = productId
        self.lotId = lotId
        dateType = override.dateType?.rawValue
        extensionMonths = override.extensionMonths
        packagedLifeMonths = override.packagedLifeMonths
        rotationMonths = override.rotationMonths
    }

    func toCore() throws -> ShelfLifeOverride {
        let decoder = ColumnDecoder(table: Self.databaseTableName)
        return ShelfLifeOverride(
            dateType: try decoder.optionalEnum("dateType", dateType),
            extensionMonths: extensionMonths,
            packagedLifeMonths: packagedLifeMonths,
            rotationMonths: rotationMonths
        )
    }
}
