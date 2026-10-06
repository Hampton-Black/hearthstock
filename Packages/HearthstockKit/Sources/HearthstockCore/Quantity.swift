import Foundation

/// What a quantity measures. Each kind has one base unit, which is how lots store quantities.
public enum UnitKind: String, Hashable, Sendable, Codable, CaseIterable {
    case mass
    case volume
    case energy
    case count

    public var baseUnit: QuantityUnit {
        switch self {
        case .mass: .pound
        case .volume: .gallon
        case .energy: .wattHour
        case .count: .count
        }
    }
}

/// A unit a quantity can be entered in. Volumes are US customary (US gallon, US fluid ounce).
public enum QuantityUnit: Hashable, Sendable, Codable {
    // Mass
    case pound
    case ounce
    case kilogram
    case gram
    // Volume
    case gallon
    case quart
    case liter
    case milliliter
    case fluidOunce
    // Energy
    case wattHour
    case kilowattHour
    /// Battery capacity at a nominal voltage: Wh = mAh × V / 1000.
    case milliampHour(volts: Double)
    // Count
    case count

    public var kind: UnitKind {
        switch self {
        case .pound, .ounce, .kilogram, .gram: .mass
        case .gallon, .quart, .liter, .milliliter, .fluidOunce: .volume
        case .wattHour, .kilowattHour, .milliampHour: .energy
        case .count: .count
        }
    }

    /// How many of the kind's base unit one of this unit is.
    func baseUnitsPerUnit() throws(UnitConversionError) -> Double {
        switch self {
        case .pound: return 1
        case .ounce: return 1.0 / 16
        case .kilogram: return 1 / Self.kilogramsPerPound
        case .gram: return 1 / (Self.kilogramsPerPound * 1000)
        case .gallon: return 1
        case .quart: return 1.0 / 4
        case .liter: return 1 / Self.litersPerGallon
        case .milliliter: return 1 / (Self.litersPerGallon * 1000)
        case .fluidOunce: return 1.0 / 128
        case .wattHour: return 1
        case .kilowattHour: return 1000
        case .milliampHour(let volts):
            guard volts.isFinite, volts > 0 else { throw .invalidVoltage }
            return volts / 1000
        case .count: return 1
        }
    }

    private static let kilogramsPerPound = 0.45359237
    private static let litersPerGallon = 3.785411784
}

public enum UnitConversionError: Error, Hashable, Sendable {
    case incompatibleKinds(from: UnitKind, to: UnitKind)
    /// A mAh unit needs a finite, positive voltage.
    case invalidVoltage
}

/// An amount in a specific unit.
public struct Quantity: Hashable, Sendable, Codable {
    public var value: Double
    public var unit: QuantityUnit

    public init(value: Double, unit: QuantityUnit) {
        self.value = value
        self.unit = unit
    }

    /// This quantity expressed in another unit of the same kind.
    public func converted(to target: QuantityUnit) throws(UnitConversionError) -> Quantity {
        guard unit.kind == target.kind else {
            throw .incompatibleKinds(from: unit.kind, to: target.kind)
        }
        let base = value * (try unit.baseUnitsPerUnit())
        return Quantity(value: base / (try target.baseUnitsPerUnit()), unit: target)
    }

    /// This quantity in its kind's base unit (lb, gal, Wh, count).
    /// Throws only for a mAh quantity with a non-positive or non-finite voltage.
    public func inBaseUnit() throws(UnitConversionError) -> Quantity {
        try converted(to: unit.kind.baseUnit)
    }
}
