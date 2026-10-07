import Foundation
import Testing
@testable import HearthstockCore

@Suite struct ProductDraftTests {
    @Test func draftBecomesAProductWithTidiedFields() throws {
        let draft = ProductDraft(
            name: "  Long-grain white rice ", barcode: "  ", category: .food, unitKind: .mass, kcalPerBaseUnit: 1630,
            potableWaterGalPerBaseUnit: 3, shelfLifeProfileKey: "white_rice")
        let id = ProductID()
        let product = try draft.product(id: id)
        #expect(product == Product(
            id: id, name: "Long-grain white rice", category: .food, role: .supply, unitKind: .mass,
            kcalPerBaseUnit: 1630, shelfLifeProfileKey: "white_rice"))
    }

    @Test func waterKeepsGallonsAndDropsCalories() throws {
        let draft = ProductDraft(
            name: "Water jug", barcode: " 0123 ", category: .water, unitKind: .volume, kcalPerBaseUnit: 10,
            potableWaterGalPerBaseUnit: 1)
        let product = try draft.product()
        #expect(product.kcalPerBaseUnit == nil)
        #expect(product.potableWaterGalPerBaseUnit == 1)
        #expect(product.barcode == "0123")
        #expect(product.shelfLifeProfileKey == "bottled_water")
    }

    @Test(arguments: [
        (ProductDraft(name: " "), ProductDraftError.emptyName),
        (ProductDraft(name: "Rice", kcalPerBaseUnit: -1), .invalidCalories),
        (ProductDraft(name: "Rice", kcalPerBaseUnit: .nan), .invalidCalories),
        (ProductDraft(name: "Water", category: .water, unitKind: .volume, potableWaterGalPerBaseUnit: -0.5), .invalidWater),
    ])
    func invalidDraftsAreRefused(draft: ProductDraft, error: ProductDraftError) {
        #expect(throws: error) { try draft.product() }
    }

    @Test func editingRoundTripsAProduct() throws {
        let product = Product(
            name: "Black beans", barcode: "123", category: .food, role: .supply, unitKind: .count,
            kcalPerBaseUnit: 385, shelfLifeProfileKey: "canned_low_acid")
        #expect(try ProductDraft(product).product(id: product.id) == product)
    }

    @Test(arguments: [
        (32_600.0, Quantity(value: 20, unit: .pound), UnitKind.mass, 1630.0),
        (3_600, Quantity(value: 12, unit: .count), .count, 300),
        (1_000, Quantity(value: 1, unit: .kilogram), .mass, 1000 * 0.45359237),
        (0, Quantity(value: 5, unit: .pound), .mass, 0),
    ])
    func perPackageHelperConvertsToTheBaseUnit(kcal: Double, size: Quantity, kind: UnitKind, expected: Double) throws {
        #expect(isApproximately(try ProductDraft.kcalPerBaseUnit(kcalPerPackage: kcal, packageSize: size, unitKind: kind), expected))
    }

    @Test(arguments: [
        Quantity(value: 0, unit: .pound),
        Quantity(value: -2, unit: .pound),
        Quantity(value: 2, unit: .gallon),  // wrong kind for a mass product
        Quantity(value: .infinity, unit: .pound),
    ])
    func perPackageHelperRefusesABadPackageSize(size: Quantity) {
        #expect(throws: ProductDraftError.invalidPackageSize) {
            try ProductDraft.kcalPerBaseUnit(kcalPerPackage: 1000, packageSize: size, unitKind: .mass)
        }
    }

    @Test func defaults() {
        #expect(ProductDraft.defaultPotableWaterGalPerBaseUnit(category: .water, unitKind: .volume) == 1)
        #expect(ProductDraft.defaultPotableWaterGalPerBaseUnit(category: .water, unitKind: .count) == nil)
        #expect(ProductDraft.defaultPotableWaterGalPerBaseUnit(category: .food, unitKind: .volume) == nil)
        let table = try! ShelfLifeProfileTable.bundledDefaults()
        for category in Category.allCases {
            #expect(table[ProductDraft.defaultProfileKey(for: category)] != nil, "\(category)")
        }
        #expect(ProductDraft().role == .supply)
    }
}
