import Foundation

/// A repository call that couldn't complete because of the data it was given, not because storage failed.
/// Storage failures surface as the store's own errors.
public enum RepositoryError: Error, Hashable, Sendable {
    case siteNotFound(SiteID)
    case locationNotFound(LocationID)
    case lotNotFound(LotID)
    /// The location still holds lots (archived ones included); move or delete them first.
    case locationHasLots(LocationID)
    /// The location is still the parent of other locations.
    case locationHasChildren(LocationID)
    /// The location is a kit's location; kits can't be removed yet.
    case locationHasKit(LocationID)
    /// Consumption must be a finite amount greater than zero.
    case invalidAmount(Double)
    /// Archived lots are history and can't be consumed.
    case lotArchived(LotID)
    /// More was requested than the lot holds; the lot is unchanged.
    case insufficientQuantity(LotID, available: Double, requested: Double)
}

public protocol SiteRepository: Sendable {
    /// Every site, oldest first.
    func list() async throws -> [Site]
    func get(_ id: SiteID) async throws -> Site?
    /// Inserts the site, or renames it if it exists.
    func save(_ site: Site) async throws
    /// The oldest site, creating one named "Home" first if none exists. Safe to call repeatedly.
    func ensureDefaultSite() async throws -> Site
}

public protocol PersonRepository: Sendable {
    func list(siteID: SiteID) async throws -> [Person]
    func save(_ person: Person) async throws
    func delete(_ id: PersonID) async throws
}

public protocol LocationRepository: Sendable {
    func list(siteID: SiteID) async throws -> [Location]
    func save(_ location: Location) async throws
    /// Throws `RepositoryError.locationHasLots`, `.locationHasChildren` or `.locationHasKit` when the
    /// location is still in use. Deleting a location that doesn't exist does nothing.
    func delete(_ id: LocationID) async throws
}

public protocol ProductRepository: Sendable {
    func get(_ id: ProductID) async throws -> Product?
    func find(barcode: String) async throws -> Product?
    /// Products whose name contains `name`, ignoring ASCII case, ordered by name. An empty `name` matches all.
    func search(name: String) async throws -> [Product]
    func save(_ product: Product) async throws
}

public protocol LotRepository: Sendable {
    func list(siteID: SiteID, includeArchived: Bool) async throws -> [Lot]
    /// Inserts or updates the lot. Its site is its location's site; throws
    /// `RepositoryError.locationNotFound` if the location doesn't exist.
    func save(_ lot: Lot) async throws
    /// Takes `amount` (in the product's base unit) out of the lot and returns it as stored. A lot that reaches
    /// zero is archived. Throws `RepositoryError.insufficientQuantity` if `amount` exceeds what's left, leaving
    /// the lot unchanged.
    @discardableResult
    func consume(_ id: LotID, amount: Double) async throws -> Lot
    func archive(_ id: LotID) async throws
    /// The unarchived lots of `siteID`, in `list` order: the current value first, then again after each write
    /// that changes them. A write to another site, or one that leaves the lots as they were, emits nothing.
    /// The stream ends when its consumer stops iterating, or throws if reading fails.
    func observeLots(siteID: SiteID) -> AsyncThrowingStream<[Lot], any Error>
}

public protocol KitRepository: Sendable {
    /// Kits whose home is `siteID`.
    func list(siteID: SiteID) async throws -> [Kit]
    /// Inserts or updates the kit and marks its location as that kit's location. The home site is the
    /// location's site; throws `RepositoryError.locationNotFound` if the location doesn't exist.
    func save(_ kit: Kit) async throws
}

/// Everything `RunwayCalculator` needs for one site.
public struct RunwayInputs: Hashable, Sendable {
    public var site: Site
    public var occupants: [Person]
    /// Unarchived lots only.
    public var lots: [Lot]
    public var products: [Product]
    public var locations: [Location]
    public var kits: [Kit]

    public init(
        site: Site,
        occupants: [Person],
        lots: [Lot],
        products: [Product],
        locations: [Location],
        kits: [Kit]
    ) {
        self.site = site
        self.occupants = occupants
        self.lots = lots
        self.products = products
        self.locations = locations
        self.kits = kits
    }
}

public protocol RunwayInputsLoader: Sendable {
    /// A consistent snapshot of a site, read in one transaction so a write in progress is never half-seen.
    /// Throws `RepositoryError.siteNotFound` if the site doesn't exist.
    func load(siteID: SiteID) async throws -> RunwayInputs

    /// `load`'s snapshot of `siteID`: the current value first, then again after each write that changes it.
    /// A write to another site, or one that leaves this site's inputs as they were, emits nothing. The stream
    /// ends when its consumer stops iterating, and throws `RepositoryError.siteNotFound` if the site doesn't
    /// exist (or any storage error if reading fails).
    func observeRunwayInputs(siteID: SiteID) -> AsyncThrowingStream<RunwayInputs, any Error>
}

extension RunwayCalculator {
    /// Runway for the site `inputs` was loaded for.
    public static func runway(
        for inputs: RunwayInputs,
        profiles: ShelfLifeProfileTable,
        on today: CalendarDate,
        targets: [Double] = defaultTargets
    ) -> SiteRunway {
        runway(
            for: inputs.site,
            occupants: inputs.occupants,
            lots: inputs.lots,
            products: inputs.products,
            locations: inputs.locations,
            kits: inputs.kits,
            profiles: profiles,
            on: today,
            targets: targets
        )
    }
}
