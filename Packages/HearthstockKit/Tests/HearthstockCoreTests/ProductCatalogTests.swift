import Foundation
import Testing
@testable import HearthstockCore

@Suite struct ProductCatalogTests {
    static func product(_ name: String) -> Product {
        Product(name: name, category: .food, role: .supply, unitKind: .count, shelfLifeProfileKey: "unknown_food")
    }

    static func lot(_ product: Product, acquired: String, archived: Bool = false) -> Lot {
        Lot(
            productID: product.id, quantity: archived ? 0 : 1, acquiredDate: CalendarDate(iso: acquired)!,
            locationID: LocationID(), archived: archived)
    }

    @Test func aProductWithNoLotsIsStillListedAndCanBeDeleted() {
        let rows = ProductCatalog.rows(products: [Self.product("Corn")], lots: [])
        #expect(rows.count == 1)
        #expect(rows[0].lotCount == 0)
        #expect(rows[0].canDelete)
    }

    @Test func lotsSplitIntoCurrentAndUsedUpNewestFirst() {
        let corn = Self.product("Corn")
        let current = Self.lot(corn, acquired: "2026-05-01")
        let older = Self.lot(corn, acquired: "2024-01-01", archived: true)
        let newer = Self.lot(corn, acquired: "2025-01-01", archived: true)
        let row = ProductCatalog.rows(products: [corn], lots: [older, current, newer])[0]
        #expect(row.currentLots == [current])
        #expect(row.usedUpLots == [newer, older])
    }

    @Test func aUsedUpLotAloneBlocksDelete() {
        let corn = Self.product("Corn")
        let row = ProductCatalog.rows(products: [corn], lots: [Self.lot(corn, acquired: "2024-01-01", archived: true)])[0]
        #expect(!row.canDelete)
    }

    @Test func anotherProductsLotsDontCount() {
        let corn = Self.product("Corn"), rice = Self.product("Rice")
        let rows = ProductCatalog.rows(products: [corn, rice], lots: [Self.lot(rice, acquired: "2026-01-01")])
        #expect(rows.map(\.lotCount) == [0, 1])
    }

    @Test func sortedByNameIgnoringCaseAndAccents() {
        let names = ["rice", "Élan beans", "Corn"].map(Self.product)
        #expect(ProductCatalog.rows(products: names, lots: []).map(\.product.name) == ["Corn", "Élan beans", "rice"])
    }

    @Test(arguments: [("JALAP", 1), ("jalapeno", 1), ("  corn ", 1), ("", 2), ("zzz", 0)])
    func searchIgnoresCaseAndAccents(query: String, count: Int) {
        let products = ["Jalapeño slices", "Corn"].map(Self.product)
        #expect(ProductCatalog.rows(products: products, lots: [], query: query).count == count)
    }
}
