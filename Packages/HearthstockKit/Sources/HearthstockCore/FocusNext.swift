import Foundation

/// The unit a category's runway amounts are in: kcal for food, gallons for water.
public enum RunwayUnit: String, Hashable, Sendable {
    case kcal
    case gallon
}

extension Category {
    /// Nil for categories that have no runway yet.
    public var runwayUnit: RunwayUnit? {
        switch self {
        case .food: .kcal
        case .water: .gallon
        default: nil
        }
    }
}

/// One entry of the dashboard's "Focus next" list. Data only; wording is the app's job.
///
/// The spec's items 3–5 (missing capabilities, kit gaps, maintenance) arrive as new cases in later slices.
public enum FocusItem: Hashable, Sendable {
    /// The site has no occupants, so no days can be computed.
    case noOccupants
    /// The limiting category needs `amount` more (in `unit`) to reach `targetDays`.
    case reachTarget(category: Category, amount: Double, unit: RunwayUnit, targetDays: Double)
    /// A Caution or Inspect lot: eat or rotate it.
    case rotate(LotStatus)
    /// A Use soon lot: its printed date is close.
    case useSoon(LotStatus)
    /// Food lots that count toward runway but whose product has no calories, and those products.
    case missingNutrition(lots: [LotID], products: [ProductID])
    /// Water lots measured in a non-volume unit with no gallons per unit, and those products.
    case missingWaterVolume(lots: [LotID], products: [ProductID])
}

public enum FocusNext {
    /// The Focus next list in the spec's priority order: problems that stop the math, then the limiting
    /// category's next target, then Caution and Inspect lots (soonest usable-by first), then Use soon lots (by
    /// printed date), then lots the runway couldn't count for missing data. Ties go by product name, then lot ID.
    ///
    /// Expired lots aren't listed: they're not "eat or rotate" any more.
    public static func items(runway: SiteRunway, statuses: [LotStatus]) -> [FocusItem] {
        var items: [FocusItem] = []
        if runway.problems.contains(.noOccupants) { items.append(.noOccupants) }

        if let target = runway.nextTarget, let unit = target.category.runwayUnit, target.shortfall > 0 {
            items.append(.reachTarget(
                category: target.category, amount: target.shortfall, unit: unit, targetDays: target.days))
        }

        let rotate = statuses.filter { $0.state == .caution || $0.state == .inspect }
            .sorted { order($0, $1, by: \.evaluation?.usableBy) }
        items += rotate.map(FocusItem.rotate)

        let useSoon = statuses.filter { $0.state == .useSoon }
            .sorted { order($0, $1, by: \.lot.printedDate) }
        items += useSoon.map(FocusItem.useSoon)

        let productByLot = Dictionary(
            statuses.compactMap { status in status.product.map { (status.lot.id, $0.id) } },
            uniquingKeysWith: { first, _ in first })
        if !runway.lotsMissingNutrition.isEmpty {
            items.append(.missingNutrition(
                lots: runway.lotsMissingNutrition,
                products: uniqued(runway.lotsMissingNutrition.compactMap { productByLot[$0] })))
        }
        if !runway.lotsMissingWaterVolume.isEmpty {
            items.append(.missingWaterVolume(
                lots: runway.lotsMissingWaterVolume,
                products: uniqued(runway.lotsMissingWaterVolume.compactMap { productByLot[$0] })))
        }
        return items
    }

    /// Earlier date first (nil last), then product name, then lot ID, so the order never depends on input order.
    private static func order(
        _ lhs: LotStatus, _ rhs: LotStatus, by date: KeyPath<LotStatus, CalendarDate?>
    ) -> Bool {
        switch (lhs[keyPath: date], rhs[keyPath: date]) {
        case let (l?, r?) where l != r: return l < r
        case (_?, nil): return true
        case (nil, _?): return false
        default: break
        }
        let lName = lhs.product?.name ?? "", rName = rhs.product?.name ?? ""
        if lName != rName { return lName.localizedStandardCompare(rName) == .orderedAscending }
        return lhs.lot.id.rawValue.uuidString < rhs.lot.id.rawValue.uuidString
    }

    private static func uniqued(_ ids: [ProductID]) -> [ProductID] {
        var seen: Set<ProductID> = []
        return ids.filter { seen.insert($0).inserted }
    }
}
