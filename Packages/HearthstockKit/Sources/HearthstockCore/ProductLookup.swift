import Foundation

/// What an online lookup knew about a barcode, decoded tolerantly: any field may be missing. Kept in the lookup
/// cache, so it's `Codable`; turned into a `ProductDraft` by `OpenFoodFacts.draft(from:barcode:profiles:)`.
public struct LookedUpProduct: Hashable, Sendable, Codable {
    public var name: String?
    /// The first listed brand.
    public var brand: String?
    /// The label's size as printed: "10.5 oz (298 g)".
    public var quantityLabel: String?
    /// The net amount of one package, in `netQuantityUnit`.
    public var netQuantity: Double?
    public var netQuantityUnit: NetUnit?
    /// Energy per 100 g (per 100 ml for drinks), converted from kJ when only kJ is given.
    public var kcalPer100: Double?
    public var kcalPerServing: Double?
    /// The serving as printed: "0.5 cup (125 g)", "1 bar (50 g)". Empty in answers cached before Slice 5.
    public var servingLabel: String?
    /// One serving's amount in `servingQuantityUnit`, as Open Food Facts gives it (its unit isn't always the
    /// label's: the corn's 125 g serving is recorded as 125 ml).
    public var servingQuantity: Double?
    public var servingQuantityUnit: NetUnit?
    public var categoryTags: [String]

    /// Net amounts are grams or millilitres once converted.
    public enum NetUnit: String, Hashable, Sendable, Codable {
        case gram
        case millilitre
    }

    public init(
        name: String? = nil, brand: String? = nil, quantityLabel: String? = nil, netQuantity: Double? = nil,
        netQuantityUnit: NetUnit? = nil, kcalPer100: Double? = nil, kcalPerServing: Double? = nil,
        servingLabel: String? = nil, servingQuantity: Double? = nil, servingQuantityUnit: NetUnit? = nil,
        categoryTags: [String] = []
    ) {
        self.name = name
        self.brand = brand
        self.quantityLabel = quantityLabel
        self.netQuantity = netQuantity
        self.netQuantityUnit = netQuantityUnit
        self.kcalPer100 = kcalPer100
        self.kcalPerServing = kcalPerServing
        self.servingLabel = servingLabel
        self.servingQuantity = servingQuantity
        self.servingQuantityUnit = servingQuantityUnit
        self.categoryTags = categoryTags
    }
}

/// The answer to "what is this barcode?". Network trouble is an answer too, never an error.
public enum LookupResult: Hashable, Sendable {
    case found(LookedUpProduct)
    case notFound
    case unavailable(LookupUnavailableReason)
}

/// Looks barcodes up online. The only implementations that touch the network live in HearthstockLookup.
public protocol ProductLookupService: Sendable {
    func lookup(_ barcode: Barcode) async -> LookupResult
    /// Asks again even when an answer is saved ("Look up online"), replacing it. Defaults to `lookup`.
    func refresh(_ barcode: Barcode) async -> LookupResult
}

extension ProductLookupService {
    public func refresh(_ barcode: Barcode) async -> LookupResult { await lookup(barcode) }
}

/// A saved lookup answer. Only found and not found are saved; "unavailable" never is (Decision 7).
public struct CachedLookup: Hashable, Sendable {
    public enum Outcome: Hashable, Sendable {
        case found(LookedUpProduct)
        case notFound
    }

    public var barcode: Barcode
    public var outcome: Outcome
    public var fetchedAt: Date

    public init(barcode: Barcode, outcome: Outcome, fetchedAt: Date) {
        self.barcode = barcode
        self.outcome = outcome
        self.fetchedAt = fetchedAt
    }

    public var result: LookupResult {
        switch outcome {
        case .found(let product): .found(product)
        case .notFound: .notFound
        }
    }
}

/// Lookup answers kept on the phone, one per barcode, so each barcode leaves the phone at most once.
public protocol LookupCacheRepository: Sendable {
    func get(_ barcode: Barcode) async throws -> CachedLookup?
    /// Inserts or replaces the barcode's entry.
    func put(_ entry: CachedLookup) async throws
    func count() async throws -> Int
    func clear() async throws
}
