import Foundation

public enum QuantityEntryError: Error, Hashable, Sendable {
    /// The amount must be a finite number greater than zero (zero is allowed only where noted).
    case invalidAmount
    /// Packs must be a whole number of at least one.
    case invalidPacks
    /// The unit isn't one of the product's kind.
    case wrongUnitKind(expected: UnitKind, got: UnitKind)
    case conversion(UnitConversionError)
}

/// An amount as a person types it: a value in any unit of the product's kind, optionally times a number of packs
/// ("24 × 0.5 L"). Converted to the product's base unit on save; lots store nothing else.
public struct QuantityEntry: Hashable, Sendable {
    public var value: Double
    public var unit: QuantityUnit
    /// Nil or 1 for a single package.
    public var packs: Int?

    public init(value: Double, unit: QuantityUnit, packs: Int? = nil) {
        self.value = value
        self.unit = unit
        self.packs = packs
    }

    /// The amount in `kind`'s base unit: 24 × 0.5 L → 3.170 gal. `allowZero` is for setting a lot's remaining
    /// quantity, where zero means used up.
    public func baseAmount(for kind: UnitKind, allowZero: Bool = false) throws(QuantityEntryError) -> Double {
        guard unit.kind == kind else { throw .wrongUnitKind(expected: kind, got: unit.kind) }
        guard value.isFinite, value > 0 || (allowZero && value == 0) else { throw .invalidAmount }
        let count = packs ?? 1
        guard count >= 1 else { throw .invalidPacks }
        do {
            return try Quantity(value: value * Double(count), unit: unit).inBaseUnit().value
        } catch {
            throw .conversion(error)
        }
    }
}

extension Lot {
    /// This lot with its remaining quantity set directly (an Adjust correction). Zero archives it, as using it up
    /// would; a positive amount on an archived lot brings it back.
    public func adjusted(toRemaining quantity: Double) -> Lot {
        var lot = self
        lot.quantity = max(0, quantity)
        lot.archived = lot.quantity == 0
        return lot
    }
}
