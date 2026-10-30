import Foundation
import Testing
@testable import HearthstockCore

/// Slice 5 Task 1: the serving label and quantity on `LookedUpProduct`.
@Suite struct ServingFieldsTests {
    struct Expected: Sendable, CustomTestStringConvertible {
        var fixture: String
        var label: String?
        var quantity: Double?
        var unit: LookedUpProduct.NetUnit?
        var testDescription: String { fixture }
    }

    static let expectations: [Expected] = [
        Expected(fixture: "corn", label: "0.5 cup (125 g)", quantity: 125, unit: .millilitre),  // as recorded
        Expected(fixture: "cinnamon-rolls", label: "2 rolls (61 g)", quantity: 61, unit: .gram),
        Expected(fixture: "protein-bar", label: "1 bar (50 g)", quantity: 50, unit: .gram),
        Expected(fixture: "rice-25lb", label: "0.25 cup (47 g)", quantity: 47, unit: .millilitre),
        Expected(fixture: "water-40pack", label: "500ml", quantity: 500, unit: .millilitre),  // the string "500"
        Expected(fixture: "campbells-soup", label: "120.0g", quantity: 120, unit: .gram),
        Expected(fixture: "barilla-penne", label: "1 portion (56 g)", quantity: 56, unit: .gram),
        Expected(fixture: "derived-rice-25lb-with-size", label: "0.25 cup (47 g)", quantity: 47, unit: .millilitre),
        Expected(fixture: "derived-soup-kj-only", label: "120.0g", quantity: 120, unit: .gram),
        Expected(fixture: "derived-water-named", label: "500ml", quantity: 500, unit: .millilitre),
    ]

    @Test(arguments: expectations)
    func fixtureDecodesItsServing(expected: Expected) throws {
        let product = try OpenFoodFactsTests.lookedUp(expected.fixture)
        #expect(product.servingLabel == expected.label)
        #expect(product.servingQuantityUnit == expected.unit)
        switch (product.servingQuantity, expected.quantity) {
        case let (actual?, wanted?): #expect(isApproximately(actual, wanted))
        case (nil, nil): break
        default: Issue.record("serving quantity \(String(describing: product.servingQuantity))")
        }
    }

    @Test func numericStringsAndOtherUnitsDecode() {
        let body = #"{"product": {"serving_size": " 1 can ", "serving_quantity": "0.35", "serving_quantity_unit": "kg"}}"#
        guard case .found(let product) = OpenFoodFacts.decode(Data(body.utf8), httpStatus: 200) else {
            Issue.record("expected found")
            return
        }
        #expect(product.servingLabel == "1 can")
        #expect(product.servingQuantity.map { isApproximately($0, 350) } == true)
        #expect(product.servingQuantityUnit == .gram)
    }

    @Test func malformedServingFieldsAreLeftEmpty() {
        let body = #"{"product": {"serving_size": "", "serving_quantity": "a few", "serving_quantity_unit": "g"}}"#
        #expect(OpenFoodFacts.decode(Data(body.utf8), httpStatus: 200) == .found(LookedUpProduct()))
        let noUnit = #"{"product": {"serving_quantity": 40}}"#
        #expect(OpenFoodFacts.decode(Data(noUnit.utf8), httpStatus: 200) == .found(LookedUpProduct()))
    }

    /// A `LookedUpProduct` as Slice 4 encoded it (sorted keys, no serving fields) decodes with them empty, and
    /// encodes back to the same bytes.
    @Test func aSlice4AnswerDecodesUnchanged() throws {
        let slice4 = #"{"brand":"Campbell's","categoryTags":["en:canned-foods"],"kcalPer100":83.33,"kcalPerServing":100,"name":"Cream Of Mushroom Soup","netQuantity":297.67,"netQuantityUnit":"gram","quantityLabel":"10.5 oz (298 g)"}"#
        let decoded = try JSONDecoder().decode(LookedUpProduct.self, from: Data(slice4.utf8))
        #expect(decoded == LookedUpProduct(
            name: "Cream Of Mushroom Soup", brand: "Campbell's", quantityLabel: "10.5 oz (298 g)", netQuantity: 297.67,
            netQuantityUnit: .gram, kcalPer100: 83.33, kcalPerServing: 100, categoryTags: ["en:canned-foods"]))
        #expect(decoded.servingLabel == nil && decoded.servingQuantity == nil && decoded.servingQuantityUnit == nil)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        #expect(String(decoding: try encoder.encode(decoded), as: UTF8.self) == slice4)
    }

    @Test func servingFieldsRoundTripThroughJSON() throws {
        let corn = try OpenFoodFactsTests.lookedUp("corn")
        #expect(try JSONDecoder().decode(LookedUpProduct.self, from: JSONEncoder().encode(corn)) == corn)
    }
}
