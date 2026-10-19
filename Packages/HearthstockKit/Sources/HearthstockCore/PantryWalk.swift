import Foundation

/// One pantry walk: a location, and every save made during it in order, with what undoing each takes. Pure: the app
/// performs the writes and the undo plans; time is passed in.
///
/// Each Add is saved when it's tapped (Slice 4 Decision 15), so leaving halfway loses nothing; Undo reverses the most
/// recent action.
public struct PantryWalk: Hashable, Sendable {
    /// How a walk lot's printed date was left.
    public enum DateEntry: Hashable, Sendable {
        case printed
        /// Marked "no printed date": it ages from an estimate.
        case noPrintedDate
        /// Skipped: the lot is flagged as missing a date.
        case missing
        /// The profile needs no date (stored tap water, honey).
        case notNeeded
    }

    public enum Action: Hashable, Sendable {
        /// A new lot of an existing product.
        case createdLot(LotID, product: ProductID, amount: Double, date: DateEntry)
        /// A new product and its first lot, saved together.
        case createdProductAndLot(LotID, product: ProductID, amount: Double, date: DateEntry)
        /// `amount` added to an existing lot ("Add another", "same date as one of these").
        case added(LotID, product: ProductID, amount: Double)

        public var lotID: LotID {
            switch self {
            case .createdLot(let lot, _, _, _), .createdProductAndLot(let lot, _, _, _), .added(let lot, _, _): lot
            }
        }

        public var productID: ProductID {
            switch self {
            case .createdLot(_, let product, _, _), .createdProductAndLot(_, let product, _, _), .added(_, let product, _):
                product
            }
        }

        public var amount: Double {
            switch self {
            case .createdLot(_, _, let amount, _), .createdProductAndLot(_, _, let amount, _), .added(_, _, let amount):
                amount
            }
        }
    }

    /// What reversing an action takes, in repository calls.
    public enum Undo: Hashable, Sendable {
        /// `LotRepository.delete`.
        case deleteLot(LotID)
        /// `LotRepository.delete`, then `ProductRepository.deleteIfUnused`.
        case deleteLotAndProduct(LotID, ProductID)
        /// `LotRepository.consume` of the amount that was added.
        case consume(LotID, amount: Double)
    }

    /// One row of the summary: a product and how many times it was added this walk.
    public struct Group: Hashable, Sendable {
        public var productID: ProductID
        public var times: Int
        /// The walk's lots of this product, first first.
        public var lots: [LotID]
    }

    public let locationID: LocationID
    public let startedAt: Date
    public private(set) var actions: [Action] = []

    public init(locationID: LocationID, startedAt: Date) {
        self.locationID = locationID
        self.startedAt = startedAt
    }

    public mutating func record(_ action: Action) {
        actions.append(action)
    }

    public var lastAction: Action? { actions.last }

    /// Removes the most recent action and returns how to reverse its write.
    public mutating func undoLast() -> Undo? {
        guard let action = actions.popLast() else { return nil }
        return Self.undo(for: action)
    }

    public static func undo(for action: Action) -> Undo {
        switch action {
        case .createdLot(let lot, _, _, _): .deleteLot(lot)
        case .createdProductAndLot(let lot, let product, _, _): .deleteLotAndProduct(lot, product)
        case .added(let lot, _, let amount): .consume(lot, amount: amount)
        }
    }

    /// Adds made: the "N added this walk" pill and the summary's item count.
    public var itemCount: Int { actions.count }

    /// Distinct lots created or added to.
    public var lotCount: Int { Set(actions.map(\.lotID)).count }

    /// By product, in the order each was first added (the summary's ×N list).
    public var groups: [Group] {
        var order: [ProductID] = []
        var byProduct: [ProductID: Group] = [:]
        for action in actions {
            if byProduct[action.productID] == nil {
                order.append(action.productID)
                byProduct[action.productID] = Group(productID: action.productID, times: 0, lots: [])
            }
            byProduct[action.productID]!.times += 1
            if !byProduct[action.productID]!.lots.contains(action.lotID) {
                byProduct[action.productID]!.lots.append(action.lotID)
            }
        }
        return order.map { byProduct[$0]! }
    }

    /// Lots this walk created without a printed date (and not marked as having none): "N items need a date".
    public var lotsNeedingADate: [LotID] {
        actions.compactMap { action in
            switch action {
            case .createdLot(let lot, _, _, .missing), .createdProductAndLot(let lot, _, _, .missing): lot
            default: nil
            }
        }
    }

    /// The most recent lot created or added to for `product` this walk, for "Add another".
    public func latestLot(of product: ProductID) -> LotID? {
        actions.last { $0.productID == product }?.lotID
    }

    public func elapsed(at now: Date) -> TimeInterval {
        max(0, now.timeIntervalSince(startedAt))
    }
}
