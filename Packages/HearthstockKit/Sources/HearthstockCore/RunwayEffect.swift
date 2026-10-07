import Foundation

/// What one lot does to its site's runway on a given day. `RunwayCalculator` adds lots up by exactly these, so
/// what the lot detail and the Add confirmation say is what the dashboard counted.
public enum RunwayEffect: Hashable, Sendable {
    /// Counts toward `category`'s runway: both ends when `lowEnd` (Good, Use soon), the high end only otherwise
    /// (Caution, Inspect).
    case counts(category: Category, amount: Double, unit: RunwayUnit, lowEnd: Bool)
    /// Past its window: not counted.
    case expired(category: Category)
    /// Water that isn't potable: shown beside the water runway, never in it.
    case untreatedWater(gallons: Double)
    /// A food lot whose product has no calories.
    case missingNutrition
    /// A water lot in a non-volume unit whose product has no gallons per unit.
    case missingWaterVolume
    /// Inside a kit that doesn't count toward site runway.
    case excludedByKit
    /// A category with no runway yet (tools, medical, hygiene, power, other).
    case noRunway(Category)
    /// The lot couldn't be placed or evaluated.
    case unavailable(RunwayProblem)

    /// The checks run in the calculator's order: location, kit, product, category, profile, missing data, state.
    public init(_ status: LotStatus) {
        if case .unresolvedLocation(let id)? = status.problem {
            self = .unavailable(.unresolvedLocation(id))
            return
        }
        guard status.countsTowardSiteRunway else {
            self = .excludedByKit
            return
        }
        guard let product = status.product else {
            self = .unavailable(.missingProduct(status.lot.id))
            return
        }
        guard product.category == .food || product.category == .water, let unit = product.category.runwayUnit else {
            self = .noRunway(product.category)
            return
        }
        guard let state = status.state else {
            self = .unavailable(status.problem ?? .missingProfile(status.lot.id, product.shelfLifeProfileKey))
            return
        }
        let amount: Double
        switch product.category {
        case .food:
            guard let kcal = product.kcalPerBaseUnit else {
                self = .missingNutrition
                return
            }
            amount = status.lot.quantity * kcal
        default:
            if let galPerUnit = product.potableWaterGalPerBaseUnit, galPerUnit > 0 {
                amount = status.lot.quantity * galPerUnit
            } else if product.unitKind == .volume {
                self = state == .expired ? .expired(category: .water) : .untreatedWater(gallons: status.lot.quantity)
                return
            } else {
                self = .missingWaterVolume
                return
            }
        }
        switch state {
        case .good, .useSoon: self = .counts(category: product.category, amount: amount, unit: unit, lowEnd: true)
        case .caution, .inspect: self = .counts(category: product.category, amount: amount, unit: unit, lowEnd: false)
        case .expired: self = .expired(category: product.category)
        }
    }
}
