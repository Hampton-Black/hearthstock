import Foundation

public enum InventoryGrouping: String, Hashable, Sendable, CaseIterable {
    case location
    case category
}

/// What Inventory shows: a grouping plus search and filters, all combined.
public struct InventoryQuery: Hashable, Sendable {
    public var grouping: InventoryGrouping
    /// Matches product name or lot notes, ignoring case and diacritics. Blank matches everything.
    public var search: String
    /// Only Use soon, Caution and Inspect lots (the spec's "expiring soon").
    public var expiringSoon: Bool
    /// Only lots of this category (the Dashboard's drill-in).
    public var category: Category?

    public init(
        grouping: InventoryGrouping = .location, search: String = "", expiringSoon: Bool = false,
        category: Category? = nil
    ) {
        self.grouping = grouping
        self.search = search
        self.expiringSoon = expiringSoon
        self.category = category
    }
}

/// One group of Inventory rows.
public struct InventorySection: Hashable, Sendable, Identifiable {
    public enum Kind: Hashable, Sendable {
        /// `path` runs from the top-level location down to this one.
        case location(path: [Location])
        case category(Category)
        /// Lots whose location can't be resolved, or (grouped by category) whose product is missing.
        case unplaced
    }

    public enum ID: Hashable, Sendable {
        case location(LocationID)
        case category(Category)
        case unplaced
    }

    public var kind: Kind
    public var lots: [LotStatus]

    public init(kind: Kind, lots: [LotStatus]) {
        self.kind = kind
        self.lots = lots
    }

    public var id: ID {
        switch kind {
        case .location(let path): .location(path.last!.id)
        case .category(let category): .category(category)
        case .unplaced: .unplaced
        }
    }

    /// True when this section's location, or one above it, is a kit.
    public var isKit: Bool {
        guard case .location(let path) = kind else { return false }
        return path.contains { $0.kitID != nil }
    }
}

public enum Inventory {
    /// Lot states from most to least urgent; lots that couldn't be evaluated come first of all.
    public static let severityOrder: [LotState] = [.expired, .inspect, .caution, .useSoon, .good]

    /// `statuses` filtered by `query` and grouped. Empty groups are left out, so no matches is an empty list.
    /// `locations` must be the ones the statuses were evaluated against.
    ///
    /// By location, sections follow the location tree: each parent before its children, siblings by name. By
    /// category, sections follow `Category.allCases`. Unplaced lots come last either way. Inside a section, lots
    /// go by severity, then usable-by (soonest first, undated last), then product name.
    public static func sections(
        _ statuses: [LotStatus], locations: [Location], query: InventoryQuery
    ) -> [InventorySection] {
        let matching = statuses.filter { matches($0, query) }
        guard !matching.isEmpty else { return [] }

        var sections: [InventorySection] = []
        switch query.grouping {
        case .location:
            let byLocation = Dictionary(grouping: matching.filter { !$0.locationChain.isEmpty }, by: \.lot.locationID)
            for path in treeOrder(locations) {
                guard let lots = byLocation[path.last!.id] else { continue }
                sections.append(InventorySection(kind: .location(path: path), lots: sorted(lots)))
            }
            let unplaced = matching.filter(\.locationChain.isEmpty)
            if !unplaced.isEmpty { sections.append(InventorySection(kind: .unplaced, lots: sorted(unplaced))) }

        case .category:
            let byCategory = Dictionary(grouping: matching.filter { $0.product != nil }, by: { $0.product!.category })
            for category in Category.allCases {
                guard let lots = byCategory[category] else { continue }
                sections.append(InventorySection(kind: .category(category), lots: sorted(lots)))
            }
            let unplaced = matching.filter { $0.product == nil }
            if !unplaced.isEmpty { sections.append(InventorySection(kind: .unplaced, lots: sorted(unplaced))) }
        }
        return sections
    }

    /// Whether a status passes the query's search and filters.
    public static func matches(_ status: LotStatus, _ query: InventoryQuery) -> Bool {
        if query.expiringSoon {
            guard let state = status.state, isExpiringSoon(state) else { return false }
        }
        if let category = query.category, status.product?.category != category { return false }
        let needle = query.search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return true }
        return [status.product?.name, status.lot.notes].contains { text in
            text?.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    /// Use soon, Caution and Inspect.
    public static func isExpiringSoon(_ state: LotState) -> Bool {
        state == .useSoon || state == .caution || state == .inspect
    }

    /// Every location's path from its top-level ancestor; see `LocationTree.paths`.
    public static func treeOrder(_ locations: [Location]) -> [[Location]] {
        LocationTree.paths(locations)
    }

    static func sorted(_ lots: [LotStatus]) -> [LotStatus] {
        lots.sorted { lhs, rhs in
            let l = rank(lhs), r = rank(rhs)
            if l != r { return l < r }
            switch (lhs.evaluation?.usableBy, rhs.evaluation?.usableBy) {
            case let (a?, b?) where a != b: return a < b
            case (_?, nil): return true
            case (nil, _?): return false
            default: break
            }
            let lName = lhs.product?.name ?? "", rName = rhs.product?.name ?? ""
            if lName != rName { return lName.localizedStandardCompare(rName) == .orderedAscending }
            return lhs.lot.id.rawValue.uuidString < rhs.lot.id.rawValue.uuidString
        }
    }

    private static func rank(_ status: LotStatus) -> Int {
        guard let state = status.state else { return -1 }
        return severityOrder.firstIndex(of: state) ?? severityOrder.count
    }
}
