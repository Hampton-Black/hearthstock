import Foundation

/// One saved product and its lots at a site, for the Products list.
public struct ProductCatalogRow: Hashable, Sendable, Identifiable {
    public var product: Product
    /// Lots still in the inventory.
    public var currentLots: [Lot]
    /// Archived lots, most recently acquired first.
    public var usedUpLots: [Lot]

    public var id: ProductID { product.id }
    public var lotCount: Int { currentLots.count + usedUpLots.count }
    /// A product is deleted only once no lot of it is left, used up ones included, so history is never lost.
    public var canDelete: Bool { lotCount == 0 }

    public init(product: Product, currentLots: [Lot], usedUpLots: [Lot]) {
        self.product = product
        self.currentLots = currentLots
        self.usedUpLots = usedUpLots
    }
}

/// Every saved product with its lots, including products with nothing left. Pure: `lots` are one site's, archived
/// ones included.
public enum ProductCatalog {
    /// By name, ignoring case and accents. A non-empty `query` keeps the names containing it, ignoring the same.
    public static func rows(products: [Product], lots: [Lot], query: String = "") -> [ProductCatalogRow] {
        let byProduct = Dictionary(grouping: lots, by: \.productID)
        let wanted = fold(query.trimmingCharacters(in: .whitespacesAndNewlines))
        return products
            .filter { wanted.isEmpty || fold($0.name).contains(wanted) }
            .sorted { lhs, rhs in
                let left = fold(lhs.name), right = fold(rhs.name)
                return left != right ? left < right : lhs.id.rawValue.uuidString < rhs.id.rawValue.uuidString
            }
            .map { product in
                let own = byProduct[product.id] ?? []
                return ProductCatalogRow(
                    product: product,
                    currentLots: own.filter { !$0.archived },
                    usedUpLots: own.filter(\.archived).sorted { $0.acquiredDate > $1.acquiredDate })
            }
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
}
