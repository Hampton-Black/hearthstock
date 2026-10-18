import Foundation

/// Why an online lookup gave no answer. None of these is remembered: the next scan of the barcode tries again.
public enum LookupUnavailableReason: String, Hashable, Sendable, Codable, CaseIterable {
    case offline
    case timedOut
    case rateLimited
    case serverError
    /// Online lookup is switched off in Settings.
    case switchedOff
}

/// What a lookup of an unknown barcode said, already mapped to a draft when it found something.
public enum ScanLookup: Hashable, Sendable {
    case found(ProductDraft)
    case notFound
    case unavailable(LookupUnavailableReason)
}

/// What the app shows after a barcode is read. Decided here, never by the UI.
public enum ScanOutcome: Hashable, Sendable {
    /// A product with this barcode already exists. `lots` are its unarchived lots at this site, newest first, for
    /// "Already in your inventory"; empty goes straight to the add form.
    case known(Product, lots: [LotStatus])
    /// Unknown here and no lookup has answered yet: show "Looking up…" and run one.
    case lookingUp(Barcode)
    /// Unknown here, found online: the add form starts from this draft (barcode set).
    case found(ProductDraft)
    /// Unknown here and online: "We don't know this one yet", with only the barcode filled in.
    case notFound(ProductDraft)
    /// Unknown here and the lookup couldn't run; the same form as not found, saying why.
    case lookupUnavailable(ProductDraft, reason: LookupUnavailableReason)
}

public enum ScanResolution {
    /// Resolves a read barcode against the site's data and, for an unknown one, the lookup's answer.
    ///
    /// `products` is every product (any site); `statuses` are the site's lot statuses, so a known product whose lots
    /// are all at another site resolves to `known` with no lots. A known product ignores `lookup`.
    public static func resolve(
        _ barcode: Barcode, products: [Product], statuses: [LotStatus], lookup: ScanLookup?
    ) -> ScanOutcome {
        if let product = products.first(where: { $0.barcode == barcode.rawValue }) {
            let lots = statuses.filter { $0.lot.productID == product.id && !$0.lot.archived }
                .sorted { lhs, rhs in
                    if lhs.lot.acquiredDate != rhs.lot.acquiredDate { return lhs.lot.acquiredDate > rhs.lot.acquiredDate }
                    return lhs.lot.id.rawValue.uuidString < rhs.lot.id.rawValue.uuidString
                }
            return .known(product, lots: lots)
        }
        switch lookup {
        case nil:
            return .lookingUp(barcode)
        case .found(var draft)?:
            draft.barcode = barcode.rawValue
            return .found(draft)
        case .notFound?:
            return .notFound(emptyDraft(barcode))
        case .unavailable(let reason)?:
            return .lookupUnavailable(emptyDraft(barcode), reason: reason)
        }
    }

    /// Only the barcode, measured by count: a scanned item is usually one can, jar or bottle (Decision 12's
    /// default when the size is unknown). The form shows the choice before the first save.
    static func emptyDraft(_ barcode: Barcode) -> ProductDraft {
        ProductDraft(barcode: barcode.rawValue, category: .food, unitKind: .count)
    }
}
