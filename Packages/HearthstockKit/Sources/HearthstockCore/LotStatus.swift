import Foundation

/// One unarchived lot of a site as the runway sees it on a given day. Derived, never stored.
///
/// Every lot state the app shows comes from here, and `RunwayCalculator` counts lots from the same values, so
/// the two can't disagree.
public struct LotStatus: Hashable, Sendable, Identifiable {
    public var lot: Lot
    /// Nil when the lot's product isn't in the lookup (`problem` is `.missingProduct`).
    public var product: Product?
    /// The lot's location and its ancestors, nearest first (`locationChain.last` is the top level). Empty when
    /// the location is missing or its chain loops (`problem` is `.unresolvedLocation`).
    public var locationChain: [Location]
    /// The climate the lot is evaluated under: its own override, else the nearest class in its chain.
    public var climate: ClimateClass
    /// A location's multiplier override in force for this lot; nil uses the class default.
    public var windowMultiplierOverride: Double?
    public var humidity: Humidity
    /// The profile after product and lot overrides; nil when the product's key isn't in the table.
    public var profile: ShelfLifeProfile?
    /// Nil when the lot can't be evaluated (`problem` is set).
    public var evaluation: ShelfLifeEvaluation?
    /// False when the lot sits inside a kit that doesn't count toward site runway (or its location is unresolved).
    /// Says nothing about category: a tool lot counts toward no runway either way.
    public var countsTowardSiteRunway: Bool
    /// Why the lot couldn't be placed or evaluated. Only `.unresolvedLocation`, `.missingProduct` and
    /// `.missingProfile` appear here.
    public var problem: RunwayProblem?

    public var id: LotID { lot.id }
    public var state: LotState? { evaluation?.state }

    /// The kit location the lot sits in, nearest first, if any.
    public var kitLocation: Location? { locationChain.first { $0.kitID != nil } }

    public init(
        lot: Lot,
        product: Product?,
        locationChain: [Location],
        climate: ClimateClass,
        windowMultiplierOverride: Double?,
        humidity: Humidity,
        profile: ShelfLifeProfile?,
        evaluation: ShelfLifeEvaluation?,
        countsTowardSiteRunway: Bool,
        problem: RunwayProblem?
    ) {
        self.lot = lot
        self.product = product
        self.locationChain = locationChain
        self.climate = climate
        self.windowMultiplierOverride = windowMultiplierOverride
        self.humidity = humidity
        self.profile = profile
        self.evaluation = evaluation
        self.countsTowardSiteRunway = countsTowardSiteRunway
        self.problem = problem
    }
}

public enum LotStatusEvaluator {
    /// The status of each unarchived lot of `site`, in `lots` order.
    ///
    /// A lot whose location resolves to another site is left out. A lot whose location can't be resolved is kept
    /// with `.unresolvedLocation`, since its site is unknown. Missing products and profiles are reported on the
    /// lot, never dropped. The site's notice window drives Use soon.
    public static func statuses(
        for site: Site,
        lots: [Lot],
        products: [Product],
        locations: [Location],
        kits: [Kit],
        productShelfLifeOverrides: [ProductID: ShelfLifeOverride] = [:],
        lotShelfLifeOverrides: [LotID: ShelfLifeOverride] = [:],
        profiles: ShelfLifeProfileTable,
        on today: CalendarDate
    ) -> [LotStatus] {
        let resolver = ShelfLifeProfileResolver(
            table: profiles, productOverrides: productShelfLifeOverrides, lotOverrides: lotShelfLifeOverrides)
        let productsByID = Dictionary(products.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let locationsByID = Dictionary(locations.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let kitsByID = Dictionary(kits.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let kitsByLocationID = Dictionary(kits.map { ($0.locationID, $0) }, uniquingKeysWith: { first, _ in first })

        var statuses: [LotStatus] = []
        for lot in lots where !lot.archived {
            let product = productsByID[lot.productID]
            guard let chain = RunwayCalculator.locationChain(from: lot.locationID, locations: locationsByID) else {
                statuses.append(LotStatus(
                    lot: lot, product: product, locationChain: [], climate: lot.climateOverride ?? .fallback,
                    windowMultiplierOverride: nil, humidity: .dry, profile: nil, evaluation: nil,
                    countsTowardSiteRunway: false, problem: .unresolvedLocation(lot.id)))
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
            let climate = StorageClimate(lot: lot, chain: chain)
            let humidity = chain.lazy.compactMap(\.humidity).first ?? .dry

            var status = LotStatus(
                lot: lot, product: product, locationChain: chain, climate: climate.climateClass,
                windowMultiplierOverride: climate.windowMultiplier, humidity: humidity, profile: nil,
                evaluation: nil, countsTowardSiteRunway: !excludedByKit, problem: nil)
            guard let product else {
                status.problem = .missingProduct(lot.id)
                statuses.append(status)
                continue
            }
            guard let profile = resolver.profile(for: lot, product: product) else {
                status.problem = .missingProfile(lot.id, product.shelfLifeProfileKey)
                statuses.append(status)
                continue
            }
            status.profile = profile
            status.evaluation = ShelfLifeEvaluator.evaluate(
                lot, profile: profile, climate: climate.climateClass, humidity: humidity,
                windowMultiplier: climate.windowMultiplier, noticeWindowDays: site.noticeWindowDays, on: today)
            statuses.append(status)
        }
        return statuses
    }

    /// Statuses for the site `inputs` was loaded for.
    public static func statuses(
        for inputs: RunwayInputs,
        profiles: ShelfLifeProfileTable,
        on today: CalendarDate
    ) -> [LotStatus] {
        statuses(
            for: inputs.site,
            lots: inputs.lots,
            products: inputs.products,
            locations: inputs.locations,
            kits: inputs.kits,
            productShelfLifeOverrides: inputs.productShelfLifeOverrides,
            lotShelfLifeOverrides: inputs.lotShelfLifeOverrides,
            profiles: profiles,
            on: today
        )
    }
}
