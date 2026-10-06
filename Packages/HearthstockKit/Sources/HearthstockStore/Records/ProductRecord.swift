import Foundation
import GRDB
import HearthstockCore

struct ProductRecord: StoredRecord, Equatable {
    static let databaseTableName = "product"

    var id: String
    var name: String
    var barcode: String?
    var category: String
    var role: String
    var unitKind: String
    var kcalPerBaseUnit: Double?
    var potableWaterGalPerBaseUnit: Double?
    var shelfLifeProfileKey: String
    var createdAt: Date?
    var updatedAt: Date?

    init(_ product: Product) {
        id = product.id.stored
        name = product.name
        barcode = product.barcode
        category = product.category.rawValue
        role = product.role.rawValue
        unitKind = product.unitKind.rawValue
        kcalPerBaseUnit = product.kcalPerBaseUnit
        potableWaterGalPerBaseUnit = product.potableWaterGalPerBaseUnit
        shelfLifeProfileKey = product.shelfLifeProfileKey.rawValue
    }

    func toCore() throws -> Product {
        let decoder = ColumnDecoder(table: Self.databaseTableName)
        return Product(
            id: try decoder.id("id", id),
            name: name,
            barcode: barcode,
            category: try decoder.enum("category", category),
            role: try decoder.enum("role", role),
            unitKind: try decoder.enum("unitKind", unitKind),
            kcalPerBaseUnit: kcalPerBaseUnit,
            potableWaterGalPerBaseUnit: potableWaterGalPerBaseUnit,
            shelfLifeProfileKey: ShelfLifeProfileKey(rawValue: shelfLifeProfileKey)
        )
    }
}
