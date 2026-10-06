import Foundation
import Testing
@testable import HearthstockCore

@Suite struct QuantityTests {
    // MARK: Kinds and base units

    @Test(arguments: [
        (UnitKind.mass, QuantityUnit.pound),
        (.volume, .gallon),
        (.energy, .wattHour),
        (.count, .count),
    ])
    func baseUnitPerKind(kind: UnitKind, base: QuantityUnit) {
        #expect(kind.baseUnit == base)
        #expect(base.kind == kind)
    }

    @Test(arguments: [
        (QuantityUnit.pound, UnitKind.mass), (.ounce, .mass), (.kilogram, .mass), (.gram, .mass),
        (.gallon, .volume), (.quart, .volume), (.liter, .volume), (.milliliter, .volume), (.fluidOunce, .volume),
        (.wattHour, .energy), (.kilowattHour, .energy), (.milliampHour(volts: 3.7), .energy),
        (.count, .count),
    ])
    func unitKinds(unit: QuantityUnit, kind: UnitKind) {
        #expect(unit.kind == kind)
    }

    // MARK: Conversion to base unit

    @Test(arguments: [
        // Bead examples
        (Quantity(value: 9, unit: .kilogram), 19.84, 0.005),
        (Quantity(value: 24 * 0.5, unit: .liter), 3.17, 0.005),
        (Quantity(value: 16, unit: .fluidOunce), 0.125, 1e-9),
        (Quantity(value: 20_000, unit: .milliampHour(volts: 3.7)), 74, 1e-9),
        // Mass
        (Quantity(value: 20, unit: .pound), 20, 1e-9),
        (Quantity(value: 16, unit: .ounce), 1, 1e-9),
        (Quantity(value: 1, unit: .kilogram), 2.20462262, 1e-8),
        (Quantity(value: 453.59237, unit: .gram), 1, 1e-9),
        // Volume
        (Quantity(value: 4, unit: .quart), 1, 1e-9),
        (Quantity(value: 3.785411784, unit: .liter), 1, 1e-9),
        (Quantity(value: 3785.411784, unit: .milliliter), 1, 1e-9),
        (Quantity(value: 128, unit: .fluidOunce), 1, 1e-9),
        // Energy
        (Quantity(value: 1.5, unit: .kilowattHour), 1500, 1e-9),
        (Quantity(value: 100, unit: .wattHour), 100, 1e-9),
        (Quantity(value: 10_000, unit: .milliampHour(volts: 5)), 50, 1e-9),
        // Count
        (Quantity(value: 12, unit: .count), 12, 1e-9),
        // Zero stays zero
        (Quantity(value: 0, unit: .kilogram), 0, 1e-12),
    ])
    func convertsToBaseUnit(quantity: Quantity, expected: Double, tolerance: Double) throws {
        let base = try quantity.inBaseUnit()
        #expect(base.unit == quantity.unit.kind.baseUnit)
        #expect(isApproximately(base.value, expected, tolerance: tolerance))
    }

    // MARK: Conversion between units

    @Test func convertsWithinKind() throws {
        let grams = try Quantity(value: 2, unit: .pound).converted(to: .gram)
        #expect(grams.unit == .gram)
        #expect(isApproximately(grams.value, 907.18474))

        let milliampHours = try Quantity(value: 74, unit: .wattHour).converted(to: .milliampHour(volts: 3.7))
        #expect(isApproximately(milliampHours.value, 20_000, tolerance: 1e-6))
    }

    @Test(arguments: [
        (QuantityUnit.pound, QuantityUnit.gallon),
        (.gallon, .pound),
        (.liter, .wattHour),
        (.milliampHour(volts: 3.7), .count),
        (.count, .kilogram),
    ])
    func crossKindConversionThrows(from: QuantityUnit, to: QuantityUnit) {
        #expect(throws: UnitConversionError.incompatibleKinds(from: from.kind, to: to.kind)) {
            try Quantity(value: 1, unit: from).converted(to: to)
        }
    }

    @Test(arguments: [0.0, -3.7, .nan, .infinity])
    func invalidVoltageThrows(volts: Double) {
        #expect(throws: UnitConversionError.invalidVoltage) {
            try Quantity(value: 1000, unit: .milliampHour(volts: volts)).converted(to: .wattHour)
        }
        #expect(throws: UnitConversionError.invalidVoltage) {
            try Quantity(value: 10, unit: .wattHour).converted(to: .milliampHour(volts: volts))
        }
    }

    @Test func codableRoundTrip() throws {
        let values = [
            Quantity(value: 9, unit: .kilogram),
            Quantity(value: 20_000, unit: .milliampHour(volts: 3.7)),
        ]
        let data = try JSONEncoder().encode(values)
        #expect(try JSONDecoder().decode([Quantity].self, from: data) == values)
    }
}
