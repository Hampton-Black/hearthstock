import Foundation

/// Days of supply as a range: `low` counts only in-date lots (Good and Use soon), `high` adds Caution and Inspect.
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
    /// Amount in Good and Use soon lots.
    public var lowAmount: Double
    /// Amount in Good, Use soon, Caution and Inspect lots.
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
    /// that doesn't count toward site runway. Occupants from other sites are ignored. Shelf-life
    /// overrides are looked up by product and lot ID; see `ShelfLifeProfileResolver`. Each lot's state is
    /// `LotStatusEvaluator`'s, under the site's notice window.
    public static func runway(
        for site: Site,
        occupants: [Person],
        lots: [Lot],
        products: [Product],
        locations: [Location],
        kits: [Kit],
        productShelfLifeOverrides: [ProductID: ShelfLifeOverride] = [:],
        lotShelfLifeOverrides: [LotID: ShelfLifeOverride] = [:],
        profiles: ShelfLifeProfileTable,
        on today: CalendarDate,
        targets: [Double] = defaultTargets
    ) -> SiteRunway {
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

        let statuses = LotStatusEvaluator.statuses(
            for: site, lots: lots, products: products, locations: locations, kits: kits,
            productShelfLifeOverrides: productShelfLifeOverrides, lotShelfLifeOverrides: lotShelfLifeOverrides,
            profiles: profiles, on: today)
        // Problems are reported in the order `RunwayEffect` checks: location, then kit exclusion, then product,
        // then category, then profile. A lot in an excluded kit, or of a non-runway category, reports nothing.
        for status in statuses {
            switch RunwayEffect(status) {
            case .unavailable(let problem):
                problems.append(problem)
            case .counts(let category, let amount, _, let lowEnd):
                if category == .food { food.add(amount, lowEnd: lowEnd) } else { water.add(amount, lowEnd: lowEnd) }
            case .untreatedWater(let gallons):
                untreatedNonPotableGal += gallons
            case .missingNutrition:
                lotsMissingNutrition.append(status.lot.id)
            case .missingWaterVolume:
                lotsMissingWaterVolume.append(status.lot.id)
            case .expired, .excludedByKit, .noRunway:
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
    mutating func add(_ amount: Double, lowEnd: Bool) {
        if lowEnd { lowAmount += amount }
        highAmount += amount
    }
}
