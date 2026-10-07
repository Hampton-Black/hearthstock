import Foundation

/// A repository call that couldn't complete because of the data it was given, not because storage failed.
/// Storage failures surface as the store's own errors.
public enum RepositoryError: Error, Hashable, Sendable {
    case siteNotFound(SiteID)
    case locationNotFound(LocationID)
    case lotNotFound(LotID)
    case productNotFound(ProductID)
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
    /// A site's notice window must be a whole number of days greater than zero.
    case invalidNoticeWindow(Int)
    /// A lot saved with a new product must be a lot of that product.
    case lotProductMismatch(LotID, ProductID)
    /// The product has lots, whose quantities are stored in its base unit, so its unit kind can't change.
    case unitKindLocked(ProductID)
}

public protocol SiteRepository: Sendable {
    /// Every site, oldest first.
    func list() async throws -> [Site]
    func get(_ id: SiteID) async throws -> Site?
    /// Inserts the site, or updates its name and notice window if it exists. Throws
    /// `RepositoryError.invalidNoticeWindow` unless the window is at least one day.
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
    /// Products whose name contains `name`, ignoring ASCII case, ordered by name. An empty `name` matches all,
    /// so there's no separate `list()`.
    func search(name: String) async throws -> [Product]
    /// Every product, most recently used first: by the newest of its own last edit and its lots' creation, so a
    /// product just added to or just created comes first. Ties go by name.
    func listByRecentUse() async throws -> [Product]
    /// Whether any lot (archived ones and other sites' included) is of this product.
    func hasLots(_ id: ProductID) async throws -> Bool
    /// Inserts or updates the product. Throws `RepositoryError.unitKindLocked` when an update changes the unit
    /// kind of a product that has lots.
    func save(_ product: Product) async throws
}

public protocol LotRepository: Sendable {
    func list(siteID: SiteID, includeArchived: Bool) async throws -> [Lot]
    /// Inserts or updates the lot. Its site is its location's site; throws
    /// `RepositoryError.locationNotFound` if the location doesn't exist.
    func save(_ lot: Lot) async throws
    /// Inserts a new product and a first lot of it in one transaction: if either is refused, neither is saved.
    /// Throws `RepositoryError.lotProductMismatch` unless `lot.productID` is `product.id`, and
    /// `.locationNotFound` as `save` does.
    func save(_ lot: Lot, newProduct product: Product) async throws
    /// Removes the lot and its shelf-life override, for entry mistakes (using a lot up archives it instead).
    /// Deleting a lot that doesn't exist does nothing.
    func delete(_ id: LotID) async throws
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

/// A user's edits to the bundled shelf-life table, kept per product and per lot. An override belongs to its
/// product or lot and goes with it. Saving an empty override clears it: there's no difference between
/// "nothing overridden" and "every field defers".
public protocol ShelfLifeOverrideRepository: Sendable {
    func override(for productID: ProductID) async throws -> ShelfLifeOverride?
    func override(for lotID: LotID) async throws -> ShelfLifeOverride?
    /// Replaces the product's override. Throws `RepositoryError.productNotFound` if the product doesn't exist.
    func save(_ override: ShelfLifeOverride, for productID: ProductID) async throws
    /// Replaces the lot's override. Throws `RepositoryError.lotNotFound` if the lot doesn't exist.
    func save(_ override: ShelfLifeOverride, for lotID: LotID) async throws
    /// Removes the product's override. Does nothing if there isn't one.
    func clearOverride(for productID: ProductID) async throws
    /// Removes the lot's override. Does nothing if there isn't one.
    func clearOverride(for lotID: LotID) async throws
}

public protocol KitRepository: Sendable {
    /// Kits whose home is `siteID`.
    func list(siteID: SiteID) async throws -> [Kit]
    /// Inserts or updates the kit and marks its location as that kit's location. The home site is the
    /// location's site; throws `RepositoryError.locationNotFound` if the location doesn't exist.
    func save(_ kit: Kit) async throws
    /// Removes the kit and clears its location's kit link, so the location is an ordinary one again (and can be
    /// deleted once empty). Deleting a kit that doesn't exist does nothing.
    func delete(_ id: KitID) async throws
}

/// What a backup file holds, or what the database holds now, in counts a person can check before a restore.
public struct BackupSummary: Hashable, Sendable {
    public var formatVersion: Int
    /// Nil for the live database.
    public var exportedAt: Date?
    public var siteNames: [String]
    public var people: Int
    public var locations: Int
    public var products: Int
    /// Unarchived lots.
    public var lots: Int
    public var archivedLots: Int

    public init(
        formatVersion: Int, exportedAt: Date?, siteNames: [String], people: Int, locations: Int, products: Int,
        lots: Int, archivedLots: Int
    ) {
        self.formatVersion = formatVersion
        self.exportedAt = exportedAt
        self.siteNames = siteNames
        self.people = people
        self.locations = locations
        self.products = products
        self.lots = lots
        self.archivedLots = archivedLots
    }
}

/// Whole-database backup as one JSON document.
public protocol BackupService: Sendable {
    /// Every table as a versioned JSON document.
    func export() async throws -> Data
    /// Reads a document without writing anything; throws the same errors `restore` would for an unreadable file.
    func summary(of data: Data) async throws -> BackupSummary
    /// What the database holds now.
    func currentSummary() async throws -> BackupSummary
    /// True when restoring the document would change nothing: it holds exactly the rows the database holds now
    /// (export time aside). Throws the same errors `restore` would for an unreadable file.
    func matchesCurrentData(_ data: Data) async throws -> Bool
    /// Replaces everything in the database with the document, in one transaction: a file that fails partway
    /// leaves the existing data as it was.
    func restore(_ data: Data) async throws
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
    /// Overrides on the products in `products`; a product with none is absent.
    public var productShelfLifeOverrides: [ProductID: ShelfLifeOverride]
    /// Overrides on the lots in `lots`; a lot with none is absent.
    public var lotShelfLifeOverrides: [LotID: ShelfLifeOverride]

    public init(
        site: Site,
        occupants: [Person],
        lots: [Lot],
        products: [Product],
        locations: [Location],
        kits: [Kit],
        productShelfLifeOverrides: [ProductID: ShelfLifeOverride] = [:],
        lotShelfLifeOverrides: [LotID: ShelfLifeOverride] = [:]
    ) {
        self.site = site
        self.occupants = occupants
        self.lots = lots
        self.products = products
        self.locations = locations
        self.kits = kits
        self.productShelfLifeOverrides = productShelfLifeOverrides
        self.lotShelfLifeOverrides = lotShelfLifeOverrides
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
            productShelfLifeOverrides: inputs.productShelfLifeOverrides,
            lotShelfLifeOverrides: inputs.lotShelfLifeOverrides,
            profiles: profiles,
            on: today,
            targets: targets
        )
    }
}
