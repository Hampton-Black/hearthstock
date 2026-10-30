import Foundation
import Testing
@testable import HearthstockCore

/// Slice 5 Task 2: calories per base unit in Decision 1's order.
@Suite struct CalorieFillTests {
    static func fill(
        _ fixture: String, _ kind: UnitKind = .count, servings: Double? = nil, net: Quantity? = nil,
        label: NutritionReading? = nil
    ) throws -> CalorieFill.Fill? {
        CalorieFill.kcalPerBaseUnit(
            lookedUp: try OpenFoodFactsTests.lookedUp(fixture), unitKind: kind, servingsPerContainer: servings,
            netWeight: net, label: label)
    }

    struct Expected: Sendable, CustomTestStringConvertible {
        var fixture: String
        var kind: UnitKind = .count
        var kcal: Double?
        var source: CalorieFill.Source?
        var testDescription: String { "\(fixture) \(kind)" }
    }

    /// Every fixture from the lookup alone.
    static let fixtures: [Expected] = [
        Expected(fixture: "corn"),  // per serving only: asks
        Expected(fixture: "corn", kind: .mass, kcal: 290, source: .netQuantity),  // 64 × 4.5359
        Expected(fixture: "cinnamon-rolls"),  // "2 rolls" isn't one serving
        Expected(fixture: "protein-bar", kcal: 190, source: .singleServing),
        Expected(fixture: "rice-25lb"),
        Expected(fixture: "rice-25lb", kind: .mass, kcal: 1641, source: .netQuantity),
        Expected(fixture: "water-40pack"),  // no energy at all
        Expected(fixture: "campbells-soup", kcal: 248, source: .netQuantity),
        Expected(fixture: "barilla-penne", kcal: 1620, source: .netQuantity),
        Expected(fixture: "derived-rice-25lb-with-size", kind: .mass, kcal: 1641, source: .netQuantity),
        Expected(fixture: "derived-soup-kj-only", kcal: 248, source: .netQuantity),
        Expected(fixture: "derived-water-named"),
    ]

    @Test(arguments: fixtures)
    func fixtureFills(expected: Expected) throws {
        let fill = try Self.fill(expected.fixture, expected.kind)
        #expect(fill?.value == expected.kcal)
        #expect(fill?.source == expected.source)
    }

    @Test func cornWithServings() throws {
        let fill = try #require(try Self.fill("corn", servings: 3.5))
        #expect(fill.value == 280)
        #expect(fill.source == .servings(kcalPerServing: 80, servings: 3.5))
    }

    @Test func cornWithANetWeight() throws {
        let net = Quantity(value: 15.25, unit: .ounce)
        let fill = try #require(try Self.fill("corn", net: net))
        let grams = 15.25 * 28.349523125  // 432.3 g
        #expect(fill.value == (64 * grams / 100).rounded())
        #expect(fill.value == 277)
        #expect(fill.source == .netWeight(kcalPer100: 64, netWeight: net))
    }

    @Test(arguments: ["1 bar (50 g)", "1 can (340 g)", "1 Bottle", "1 pouch", "1 packet (28g)", "1 meal",
                      "1 container (170 g)", "1 CAN"])
    func singleServings(label: String) {
        #expect(CalorieFill.isSingleServing(label))
    }

    @Test(arguments: ["2 rolls (61 g)", "1/2 cup", "0.5 cup (125 g)", "1 cup", "1 portion (56 g)", "120.0g", "",
                      "11 bars", "1.5 bars", "1"])
    func notSingleServings(label: String) {
        #expect(!CalorieFill.isSingleServing(label))
    }

    @Test func massAndVolumeNeverAsk() throws {
        for fixture in ["corn", "rice-25lb", "cinnamon-rolls", "protein-bar"] {
            let product = try OpenFoodFactsTests.lookedUp(fixture)
            #expect(!CalorieFill.asksForServings(lookedUp: product, unitKind: .mass))
            #expect(!CalorieFill.asksForServings(lookedUp: product, unitKind: .volume))
        }
        // Servings and a net weight change nothing by the pound.
        #expect(try Self.fill("rice-25lb", .mass, servings: 241, net: Quantity(value: 25, unit: .pound))?.value == 1641)
    }

    @Test func whoAsks() throws {
        #expect(CalorieFill.asksForServings(lookedUp: try OpenFoodFactsTests.lookedUp("corn"), unitKind: .count))
        #expect(!CalorieFill.asksForServings(lookedUp: try OpenFoodFactsTests.lookedUp("protein-bar"), unitKind: .count))
        #expect(!CalorieFill.asksForServings(lookedUp: try OpenFoodFactsTests.lookedUp("campbells-soup"), unitKind: .count))
        #expect(CalorieFill.asksForServings(lookedUp: nil, unitKind: .count))
        #expect(CalorieFill.offersNetWeight(lookedUp: try OpenFoodFactsTests.lookedUp("corn")))
        #expect(!CalorieFill.offersNetWeight(lookedUp: try OpenFoodFactsTests.lookedUp("water-40pack")))
        #expect(!CalorieFill.offersNetWeight(lookedUp: nil))
    }

    // MARK: Precedence

    @Test func theNetQuantityBeatsEverything() throws {
        let label = NutritionReading(caloriesPerContainer: 999)
        let fill = try Self.fill("campbells-soup", servings: 2.5, net: Quantity(value: 1, unit: .pound), label: label)
        #expect(fill == CalorieFill.Fill(value: 248, source: .netQuantity))
    }

    @Test func aSingleServingBeatsAnswers() throws {
        let fill = try Self.fill("protein-bar", servings: 4, net: Quantity(value: 200, unit: .gram))
        #expect(fill == CalorieFill.Fill(value: 190, source: .singleServing))
    }

    @Test func servingsBeatANetWeight() throws {
        let fill = try Self.fill("corn", servings: 3.5, net: Quantity(value: 15.25, unit: .ounce))
        #expect(fill?.source == .servings(kcalPerServing: 80, servings: 3.5))
    }

    @Test func aNetWeightBeatsTheLabel() throws {
        let fill = try Self.fill(
            "corn", net: Quantity(value: 15.25, unit: .ounce), label: NutritionReading(caloriesPerContainer: 300))
        #expect(fill?.value == 277)
    }

    @Test func theLabelComesLast() throws {
        let label = NutritionReading(caloriesPerServing: 80, servingsPerContainer: 3.5)
        #expect(try Self.fill("corn", label: label) == CalorieFill.Fill(value: 280, source: .label))
    }

    // MARK: The label alone

    @Test(arguments: [
        // Dual column: per container is calories per item.
        (NutritionReading(caloriesPerServing: 220, caloriesPerContainer: 440, servingsPerContainer: 2), 440.0),
        (NutritionReading(caloriesPerServing: 80, servingsPerContainer: 3.5, servingsAreApproximate: true), 280),
        // Servings from the net weight and the serving's grams: 432 g ÷ 125 g × 80.
        (NutritionReading(
            caloriesPerServing: 80, servingQuantity: Quantity(value: 125, unit: .gram),
            netWeight: Quantity(value: 432, unit: .gram)), 276),
    ] as [(NutritionReading, Double)])
    func labelOnly(reading: NutritionReading, kcal: Double) {
        let fill = CalorieFill.kcalPerBaseUnit(lookedUp: nil, unitKind: .count, label: reading)
        #expect(fill == CalorieFill.Fill(value: kcal, source: .label))
    }

    @Test func labelPerServingWithTypedServings() {
        let fill = CalorieFill.kcalPerBaseUnit(
            lookedUp: nil, unitKind: .count, servingsPerContainer: 3, label: NutritionReading(caloriesPerServing: 100))
        #expect(fill == CalorieFill.Fill(value: 300, source: .label))
    }

    @Test func aLabelAloneGivesNothingWithoutAContainerAmount() {
        #expect(CalorieFill.kcalPerBaseUnit(
            lookedUp: nil, unitKind: .count, label: NutritionReading(caloriesPerServing: 100)) == nil)
        #expect(CalorieFill.kcalPerBaseUnit(lookedUp: nil, unitKind: .count, label: NutritionReading()) == nil)
    }

    @Test func aLabelGivesCaloriesPerPound() throws {
        // 170 kcal per 47 g: 170 ÷ (47 / 453.59237) = 1640.6 per lb.
        let reading = NutritionReading(caloriesPerServing: 170, servingQuantity: Quantity(value: 47, unit: .gram))
        let fill = CalorieFill.kcalPerBaseUnit(lookedUp: nil, unitKind: .mass, label: reading)
        #expect(fill == CalorieFill.Fill(value: 1641, source: .label))
        // A serving in ml says nothing per lb.
        let ml = NutritionReading(caloriesPerServing: 170, servingQuantity: Quantity(value: 47, unit: .milliliter))
        #expect(CalorieFill.kcalPerBaseUnit(lookedUp: nil, unitKind: .mass, label: ml) == nil)
    }

    // MARK: Refused inputs

    @Test(arguments: [0.0, -2, .nan, .infinity])
    func badServingsAreRefused(servings: Double) throws {
        #expect(try Self.fill("corn", servings: servings) == nil)
    }

    @Test(arguments: [0.0, -15.25, .nan])
    func badNetWeightsAreRefused(value: Double) throws {
        #expect(try Self.fill("corn", net: Quantity(value: value, unit: .ounce)) == nil)
    }

    @Test func aNetWeightInTheWrongKindIsRefused() throws {
        #expect(try Self.fill("corn", net: Quantity(value: 3, unit: .count)) == nil)
    }

    @Test func badLookedUpValuesAreRefused() {
        let bad = LookedUpProduct(kcalPer100: .nan, kcalPerServing: -80, servingLabel: "1 bar")
        #expect(CalorieFill.kcalPerBaseUnit(lookedUp: bad, unitKind: .count, servingsPerContainer: 2,
                                            netWeight: Quantity(value: 100, unit: .gram)) == nil)
        #expect(CalorieFill.kcalPerBaseUnit(
            lookedUp: nil, unitKind: .count, label: NutritionReading(caloriesPerContainer: -5)) == nil)
    }

    @Test func energyProductsHaveNoCalories() throws {
        #expect(try Self.fill("campbells-soup", .energy) == nil)
    }

    // MARK: Drafts

    @Test func lookingUpTheBarFillsItsCalories() throws {
        let bar = try OpenFoodFactsTests.lookedUp("protein-bar")
        let (draft, filled) = ProductDraft(name: "Bar", category: .food, unitKind: .count).fillingEmptyFields(from: bar)
        #expect(filled == [.calories])
        #expect(draft.kcalPerBaseUnit == 190)
    }
}
