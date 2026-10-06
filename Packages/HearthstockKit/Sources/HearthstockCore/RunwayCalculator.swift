import Foundation

/// Days of supply as a range: `low` counts only Good lots, `high` adds Caution and Inspect.
public struct RunwayRange: Hashable, Sendable {
    public var low: Double
    public var high: Double

    public init(low: Double, high: Double) {
        self.low = low
        self.high = high
    }
}

/// One supply category's runway. Amounts are in the category's runway unit: kcal for food, gallons for water.
public struct CategoryRunway: Hashable, Sendable {
    public var category: Category
    /// Amount in Good lots.
    public var lowAmount: Double
    /// Amount in Good, Caution and Inspect lots.
    public var highAmount: Double
    /// What the site's occupants need per day.
    public var dailyNeed: Double

    public init(category: Category, lowAmount: Double, highAmount: Double, dailyNeed: Double) {
        self.category = category
        self.lowAmount = lowAmount
        self.highAmount = highAmount
        self.dailyNeed = dailyNeed
    }

    /// Nil when nobody at the site needs any of this category.
    public var days: RunwayRange? {
        guard dailyNeed > 0 else { return nil }
        return RunwayRange(low: lowAmount / dailyNeed, high: highAmount / dailyNeed)
    }
}

/// The next runway target above the effective low end, and what the limiting category lacks to reach it.
public struct RunwayTarget: Hashable, Sendable {
    public var days: Double
    public var category: Category
    /// In the category's runway unit: kcal for food, gallons for water.
    public var shortfall: Double

    public init(days: Double, category: Category, shortfall: Double) {
        self.days = days
        self.category = category
        self.shortfall = shortfall
    }
}

/// Something that kept the calculation from being complete. Returned, never thrown.
public enum RunwayProblem: Hashable, Sendable {
    /// The site has no occupants, so there are no days to compute.
    case noOccupants
    /// The lot's location, or one above it, is missing or loops; the lot is excluded.
    case unresolvedLocation(LotID)
    /// The lot's product isn't in the lookup; the lot is excluded.
    case missingProduct(LotID)
    /// The product's shelf-life profile isn't in the table; the lot is excluded.
    case missingProfile(LotID, ShelfLifeProfileKey)
}

/// A site's food and water runway on a given day. Derived, never stored.
public struct SiteRunway: Hashable, Sendable {
    public var siteID: SiteID
    public var food: CategoryRunway
    public var water: CategoryRunway
    /// Min of food and water days, low and high taken separately. Nil when either can't be computed.
    public var effective: RunwayRange?
    /// The category that sets the effective low end.
    public var limitingCategory: Category?
    /// Nil when the effective low already meets every target.
    public var nextTarget: RunwayTarget?
    /// Non-expired water that isn't potable. Shown beside the runway, never counted until treatment exists.
    public var untreatedNonPotableGal: Double
    /// Food lots whose product has no kcal data; excluded from food.
    public var lotsMissingNutrition: [LotID]
    /// Water lots measured in a non-volume unit with no gallons-per-unit; excluded from water.
    public var lotsMissingWaterVolume: [LotID]
    public var problems: [RunwayProblem]
}

public enum RunwayCalculator {
    /// Day targets the "Focus next" list works toward.
    public static let defaultTargets: [Double] = [3, 14, 30]

    /// Food and water runway for `site` on `today`.
    ///
    /// Counts only unarchived lots whose location resolves to `site`, skipping lots inside a kit
    /// that doesn't count toward site runway. Occupants from other sites are ignored.
    public static func runway(
        for site: Site,
        occupants: [Person],
        lots: [Lot],
        products: [Product],
        locations: [Location],
        kits: [Kit],
        profiles: ShelfLifeProfileTable,
        on today: CalendarDate,
        targets: [Double] = defaultTargets
    ) -> SiteRunway {
        let productsByID = Dictionary(products.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let locationsByID = Dictionary(locations.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let kitsByID = Dictionary(kits.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let kitsByLocationID = Dictionary(kits.map { ($0.locationID, $0) }, uniquingKeysWith: { first, _ in first })

        let people = occupants.filter { $0.siteID == site.id }
        var food = CategoryRunway(
            category: .food, lowAmount: 0, highAmount: 0, dailyNeed: people.reduce(0) { $0 + $1.kcalPerDay })
        var water = CategoryRunway(
            category: .water, lowAmount: 0, highAmount: 0, dailyNeed: people.reduce(0) { $0 + $1.waterGalPerDay })
        var untreatedNonPotableGal = 0.0
        var lotsMissingNutrition: [LotID] = []
        var lotsMissingWaterVolume: [LotID] = []
        var problems: [RunwayProblem] = []
        if people.isEmpty { problems.append(.noOccupants) }

        for lot in lots where !lot.archived {
            guard let chain = locationChain(from: lot.locationID, locations: locationsByID) else {
                problems.append(.unresolvedLocation(lot.id))
                continue
            }
            guard chain[0].siteID == site.id else { continue }
            let excludedByKit = chain.contains { location in
                guard let kit = location.kitID.flatMap({ kitsByID[$0] }) ?? kitsByLocationID[location.id] else {
                    // A location marked as a kit whose kit is unknown is treated as a kit that doesn't count.
                    return location.kitID != nil
                }
                return !kit.countsTowardSiteRunway
            }
            if excludedByKit { continue }

            guard let product = productsByID[lot.productID] else {
                problems.append(.missingProduct(lot.id))
                continue
            }
            guard product.category == .food || product.category == .water else { continue }
            guard let profile = profiles[product.shelfLifeProfileKey] else {
                problems.append(.missingProfile(lot.id, product.shelfLifeProfileKey))
                continue
            }

            let climate = lot.climateOverride ?? chain.lazy.compactMap(\.climateClass).first ?? .fallback
            let humidity = chain.lazy.compactMap(\.humidity).first ?? .dry
            let state = ShelfLifeEvaluator.evaluate(
                lot, profile: profile, climate: climate, humidity: humidity, on: today
            ).state

            switch product.category {
            case .food:
                guard let kcal = product.kcalPerBaseUnit else {
                    lotsMissingNutrition.append(lot.id)
                    continue
                }
                food.add(lot.quantity * kcal, state: state)
            case .water:
                if let galPerUnit = product.potableWaterGalPerBaseUnit, galPerUnit > 0 {
                    water.add(lot.quantity * galPerUnit, state: state)
                } else if product.unitKind == .volume {
                    if state != .expired { untreatedNonPotableGal += lot.quantity }
                } else {
                    lotsMissingWaterVolume.append(lot.id)
                }
            default:
                continue
            }
        }

        var effective: RunwayRange?
        var limitingCategory: Category?
        var nextTarget: RunwayTarget?
        if let foodDays = food.days, let waterDays = water.days {
            effective = RunwayRange(low: min(foodDays.low, waterDays.low), high: min(foodDays.high, waterDays.high))
            // Water wins a tie: it runs out faster in practice and is harder to make up.
            let limiting = foodDays.low < waterDays.low ? food : water
            limitingCategory = limiting.category
            if let low = effective?.low, let target = targets.sorted().first(where: { $0 > low }) {
                nextTarget = RunwayTarget(
                    days: target,
                    category: limiting.category,
                    shortfall: target * limiting.dailyNeed - limiting.lowAmount
                )
            }
        }

        return SiteRunway(
            siteID: site.id,
            food: food,
            water: water,
            effective: effective,
            limitingCategory: limitingCategory,
            nextTarget: nextTarget,
            untreatedNonPotableGal: untreatedNonPotableGal,
            lotsMissingNutrition: lotsMissingNutrition,
            lotsMissingWaterVolume: lotsMissingWaterVolume,
            problems: problems
        )
    }

    /// The location and its ancestors, nearest first. Nil if any is missing or the chain loops.
    static func locationChain(from id: LocationID, locations: [LocationID: Location]) -> [Location]? {
        var chain: [Location] = []
        var visited: Set<LocationID> = []
        var current: LocationID? = id
        while let id = current {
            guard visited.insert(id).inserted, let location = locations[id] else { return nil }
            chain.append(location)
            current = location.parentID
        }
        return chain
    }
}

extension CategoryRunway {
    mutating func add(_ amount: Double, state: LotState) {
        switch state {
        case .good:
            lowAmount += amount
            highAmount += amount
        case .caution, .inspect:
            highAmount += amount
        case .expired:
            break
        }
    }
}
