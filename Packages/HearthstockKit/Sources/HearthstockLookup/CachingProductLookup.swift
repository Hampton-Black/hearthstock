import Foundation
import HearthstockCore

/// Lookups with every answer kept on the phone (Decision 7): each barcode leaves the phone at most once.
///
/// - A saved found or not-found answer is returned without a request, whether online lookup is on or off.
/// - A fresh found or not-found answer is saved before it's returned. `unavailable` is never saved, so the next
///   scan tries again.
/// - With online lookup off (`isEnabled` false), unsaved barcodes go to `DisabledLookupService` and come back
///   `unavailable(.switchedOff)`.
/// - `refresh` skips the saved answer and replaces it: the one way to ask again ("Look up online").
///
/// A cache that can't be read or written doesn't fail the lookup; it only costs a repeat request later.
public struct CachingProductLookup: ProductLookupService {
    private let online: any ProductLookupService
    private let cache: any LookupCacheRepository
    private let isEnabled: @Sendable () -> Bool
    private let now: @Sendable () -> Date

    public init(
        online: any ProductLookupService,
        cache: any LookupCacheRepository,
        isEnabled: @escaping @Sendable () -> Bool,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.online = online
        self.cache = cache
        self.isEnabled = isEnabled
        self.now = now
    }

    public func lookup(_ barcode: Barcode) async -> LookupResult {
        if let saved = try? await cache.get(barcode) { return saved.result }
        return await ask(barcode)
    }

    public func refresh(_ barcode: Barcode) async -> LookupResult {
        await ask(barcode)
    }

    private func ask(_ barcode: Barcode) async -> LookupResult {
        let client: any ProductLookupService = isEnabled() ? online : DisabledLookupService()
        let result = await client.lookup(barcode)
        let outcome: CachedLookup.Outcome? = switch result {
        case .found(let product): .found(product)
        case .notFound: .notFound
        case .unavailable: nil
        }
        if let outcome {
            try? await cache.put(CachedLookup(barcode: barcode, outcome: outcome, fetchedAt: now()))
        }
        return result
    }
}

/// Online lookup switched off in Settings: answers without touching the network.
public struct DisabledLookupService: ProductLookupService {
    public init() {}

    public func lookup(_ barcode: Barcode) async -> LookupResult {
        .unavailable(.switchedOff)
    }
}
