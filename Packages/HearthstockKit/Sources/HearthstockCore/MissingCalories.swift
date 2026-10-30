import Foundation

/// Why a food product has no calories, for the Missing calories list (Slice 5 Task 8). Worked out from the product
/// and its saved lookup answer, since where a value came from isn't stored (Decision 10).
public enum MissingCaloriesReason: Hashable, Sendable {
    /// No barcode: typed in by hand without calories.
    case typedIn
    /// A barcode with no saved answer (lookup off or unavailable when it was added).
    case notLookedUp
    /// Open Food Facts doesn't know the barcode.
    case notFound
    /// Open Food Facts knows the product but has no calories for it.
    case noCaloriesOnline
    /// Open Food Facts has calories per serving (or per 100 g) but not the package size: the card's question was
    /// skipped, or the product predates it.
    case needsServings

    public static func reason(for product: Product, cached: CachedLookup?) -> MissingCaloriesReason {
        guard product.barcode != nil else { return .typedIn }
        switch cached?.outcome {
        case nil: return .notLookedUp
        case .notFound?: return .notFound
        case .found(let lookedUp)?:
            let entry = CalorieEntry(lookedUp: lookedUp)
            return entry.canAskServings || entry.canAskNetWeight ? .needsServings : .noCaloriesOnline
        }
    }
}

extension PantryWalk {
    /// Food products added this walk that still have no calories ("N items have no calories"), in the order first
    /// added. `products` are the site's products as they are now, so one fixed since doesn't count.
    public func productsMissingCalories(_ products: [Product]) -> [ProductID] {
        let byID = Dictionary(products.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return groups.map(\.productID).filter { id in
            guard let product = byID[id] else { return false }
            return product.category == .food && product.kcalPerBaseUnit == nil
        }
    }
}

extension NutritionReading {
    /// Live Text reads a panel a piece at a time as the camera moves: this reading with `newer`'s fields where it has
    /// them. Servings and their "about" travel together.
    public func merging(_ newer: NutritionReading) -> NutritionReading {
        var merged = self
        if let value = newer.caloriesPerServing { merged.caloriesPerServing = value }
        if let value = newer.caloriesPerContainer { merged.caloriesPerContainer = value }
        if let value = newer.servingsPerContainer {
            merged.servingsPerContainer = value
            merged.servingsAreApproximate = newer.servingsAreApproximate
        }
        if let value = newer.servingSize { merged.servingSize = value }
        if let value = newer.servingQuantity { merged.servingQuantity = value }
        if let value = newer.netWeight { merged.netWeight = value }
        return merged
    }
}
