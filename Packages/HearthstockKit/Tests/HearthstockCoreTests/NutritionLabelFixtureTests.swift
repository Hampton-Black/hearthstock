import Foundation
import Testing
@testable import HearthstockCore

/// Slice 5 Task 3: every recorded panel in `Fixtures/nutrition-labels/` reads as its `.expected.json` says.
@Suite struct NutritionLabelFixtureTests {
    struct Fixture: Sendable, CustomTestStringConvertible {
        var name: String
        var text: String
        var expected: NutritionReading
        var testDescription: String { name }
    }

    private struct ExpectedFile: Decodable {
        struct Amount: Decodable {
            var value: Double
            var unit: String
        }

        var caloriesPerServing: Double?
        var caloriesPerContainer: Double?
        var servingsPerContainer: Double?
        var servingsAreApproximate: Bool?
        var servingSize: String?
        var servingQuantity: Amount?
        var netWeight: Amount?
    }

    static let units: [String: QuantityUnit] = [
        "g": .gram, "kg": .kilogram, "oz": .ounce, "lb": .pound, "ml": .milliliter, "l": .liter,
        "fl oz": .fluidOunce, "gal": .gallon,
    ]

    /// The folder's `.txt` files, found next to its README.
    static var panelURLs: [URL] {
        guard let folder = Bundle.module.url(
            forResource: "README", withExtension: "md", subdirectory: "Fixtures/nutrition-labels"
        )?.deletingLastPathComponent(),
            let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path)
        else { return [] }
        return names.filter { $0.hasSuffix(".txt") }.map { folder.appending(path: $0) }
    }

    static var all: [Fixture] {
        panelURLs.sorted { $0.lastPathComponent < $1.lastPathComponent }.compactMap { url in
            let name = url.deletingPathExtension().lastPathComponent
            let expectedURL = url.deletingLastPathComponent().appending(path: "\(name).expected.json")
            guard let text = try? String(contentsOf: url, encoding: .utf8),
                  let data = try? Data(contentsOf: expectedURL),
                  let file = try? JSONDecoder().decode(ExpectedFile.self, from: data)
            else { return nil }
            func quantity(_ amount: ExpectedFile.Amount?) -> Quantity? {
                amount.flatMap { amount in units[amount.unit].map { Quantity(value: amount.value, unit: $0) } }
            }
            return Fixture(name: name, text: text, expected: NutritionReading(
                caloriesPerServing: file.caloriesPerServing, caloriesPerContainer: file.caloriesPerContainer,
                servingsPerContainer: file.servingsPerContainer,
                servingsAreApproximate: file.servingsAreApproximate ?? false, servingSize: file.servingSize,
                servingQuantity: quantity(file.servingQuantity), netWeight: quantity(file.netWeight)))
        }
    }

    @Test(arguments: all)
    func panelReadsAsExpected(_ fixture: Fixture) {
        let reading = NutritionLabelParser.read(fixture.text)
        #expect(reading.caloriesPerServing == fixture.expected.caloriesPerServing)
        #expect(reading.caloriesPerContainer == fixture.expected.caloriesPerContainer)
        #expect(reading.servingsAreApproximate == fixture.expected.servingsAreApproximate)
        #expect(reading.servingSize == fixture.expected.servingSize)
        for (actual, wanted) in [
            (reading.servingsPerContainer, fixture.expected.servingsPerContainer),
            (reading.servingQuantity?.value, fixture.expected.servingQuantity?.value),
            (reading.netWeight?.value, fixture.expected.netWeight?.value),
        ] {
            switch (actual, wanted) {
            case let (a?, w?): #expect(isApproximately(a, w, tolerance: 1e-6))
            case (nil, nil): break
            default: Issue.record("read \(String(describing: actual)), expected \(String(describing: wanted))")
            }
        }
        #expect(reading.servingQuantity?.unit == fixture.expected.servingQuantity?.unit)
        #expect(reading.netWeight?.unit == fixture.expected.netWeight?.unit)
    }

    /// Every `.txt` has its `.expected.json`, so a panel can't be added and silently skipped.
    @Test func everyPanelHasAnExpectation() {
        #expect(Self.all.count == Self.panelURLs.count)
        #expect(Bundle.module.url(forResource: "README", withExtension: "md", subdirectory: "Fixtures/nutrition-labels")
            != nil)
    }
}
