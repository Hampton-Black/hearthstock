import Foundation
import Testing
@testable import HearthstockCore

/// Slice 5 Task 3: reading the Nutrition Facts panel. These cases are typed in the shapes Live Text returns (line
/// breaks where the panel wraps, "Calories" on its own line in large type). The table read from Hampton's own panel
/// photos lives in `Fixtures/nutrition-labels/`.
@Suite struct NutritionLabelParserTests {
    struct Case: Sendable, CustomTestStringConvertible {
        var name: String
        var text: String
        var expected: NutritionReading
        var testDescription: String { name }
    }

    static let cases: [Case] = [
        Case(name: "2016 panel, about servings, Calories on its own line", text: """
            Nutrition Facts
            about 3.5 servings per
            container
            Serving size 1/2 cup (125g)
            Amount per serving
            Calories
            80
            % Daily Value*
            Total Fat 0.5g 1%
            Sodium 300mg 13%
            Total Carbohydrate 17g 6%
            """,
             expected: NutritionReading(
                caloriesPerServing: 80, servingsPerContainer: 3.5, servingsAreApproximate: true,
                servingSize: "1/2 cup", servingQuantity: Quantity(value: 125, unit: .gram))),
        Case(name: "older panel, servings after, Calories from Fat, footnote", text: """
            Nutrition Facts
            Serving Size 1/4 cup (47g)
            Servings Per Container about 241
            Amount Per Serving
            Calories 170 Calories from Fat 0
            % Daily Value*
            Total Fat 0g 0%
            *Percent Daily Values are based on a 2,000 calorie diet.
            Calories: 2,000 2,500
            Total Fat Less than 65g 80g
            """,
             expected: NutritionReading(
                caloriesPerServing: 170, servingsPerContainer: 241, servingsAreApproximate: true,
                servingSize: "1/4 cup", servingQuantity: Quantity(value: 47, unit: .gram))),
        Case(name: "dual column: per container wins", text: """
            Nutrition Facts
            2 servings per container
            Serving size 1 cup (240mL)
            Per serving Per container
            Calories 220 440
            % DV* % DV*
            Total Fat 5g 6% 10g 13%
            """,
             expected: NutritionReading(
                caloriesPerServing: 220, caloriesPerContainer: 440, servingsPerContainer: 2, servingSize: "1 cup",
                servingQuantity: Quantity(value: 240, unit: .milliliter))),
        Case(name: "dual column, numbers on their own lines", text: """
            Nutrition Facts
            2.5 servings per container
            Serving size 1 cup (245g)
            Per serving
            Per container
            Calories
            120
            300
            """,
             expected: NutritionReading(
                caloriesPerServing: 120, caloriesPerContainer: 300, servingsPerContainer: 2.5, servingSize: "1 cup",
                servingQuantity: Quantity(value: 245, unit: .gram))),
        Case(name: "single serving, no grams", text: """
            Nutrition Facts
            1 serving per container
            Serving size 1 bar
            Calories 190
            """,
             expected: NutritionReading(caloriesPerServing: 190, servingsPerContainer: 1, servingSize: "1 bar")),
        Case(name: "mixed fraction servings, unicode half", text: """
            Servings Per Container: About 3½
            Serving Size ½ cup (122g)
            Calories 60
            """,
             expected: NutritionReading(
                caloriesPerServing: 60, servingsPerContainer: 3.5, servingsAreApproximate: true,
                servingSize: "1/2 cup", servingQuantity: Quantity(value: 122, unit: .gram))),
        Case(name: "net weight on the panel", text: """
            NET WT 15.25 OZ (432g)
            Nutrition Facts
            Calories 80
            """,
             expected: NutritionReading(caloriesPerServing: 80, netWeight: Quantity(value: 15.25, unit: .ounce))),
        Case(name: "Daily Value numbers are never calories", text: """
            Calories
            % Daily Value*
            10%
            Total Fat 8g
            """,
             expected: NutritionReading()),
        Case(name: "kJ energy isn't read", text: "Energy 1800 kJ / 430 kcal Serving size 50 g",
             expected: NutritionReading(servingSize: "50 g")),
        Case(name: "empty", text: "", expected: NutritionReading()),
    ]

    @Test(arguments: cases)
    func reads(_ testCase: Case) {
        #expect(NutritionLabelParser.read(testCase.text) == testCase.expected)
    }

    @Test(arguments: [
        ("NET WT 15.25 OZ (432g)", Quantity(value: 15.25, unit: .ounce)),
        ("Net Wt. 1 LB 9 OZ (709g)", Quantity(value: 1.5625, unit: .pound)),
        ("NET WT. 25 LB (11.34 kg)", Quantity(value: 25, unit: .pound)),
        ("NET CONTENTS 16.9 FL OZ (500 mL)", Quantity(value: 16.9, unit: .fluidOunce)),
        ("net 1 gal (3.78 L)", Quantity(value: 1, unit: .gallon)),
        ("NET WT 2 kg", Quantity(value: 2, unit: .kilogram)),
        ("Net weight: 454g", Quantity(value: 454, unit: .gram)),
        ("NET 500 ml", Quantity(value: 500, unit: .milliliter)),
        ("NET 1.5L", Quantity(value: 1.5, unit: .liter)),
    ])
    func netWeights(text: String, expected: Quantity) throws {
        let read = try #require(NutritionLabelParser.read(text).netWeight)
        #expect(read.unit == expected.unit)
        #expect(isApproximately(read.value, expected.value))
    }

    @Test(arguments: ["Net Carbs 5g", "Internet 4 lb", "Calories 80"])
    func noNetWeight(text: String) {
        #expect(NutritionLabelParser.read(text).netWeight == nil)
    }

    @Test func aMissingFieldStaysEmpty() {
        let reading = NutritionLabelParser.read("Serving size 2 rolls (61g)\nCalories 230")
        #expect(reading.servingsPerContainer == nil)
        #expect(reading.caloriesPerContainer == nil)
        #expect(reading.netWeight == nil)
        #expect(reading.caloriesPerServing == 230)
        #expect(reading.servingSize == "2 rolls")
    }

    @Test func calorieCountsWithThousandsSeparators() {
        let reading = NutritionLabelParser.read("Per serving Per container\nCalories 170 41,000")
        #expect(reading.caloriesPerServing == 170)
        #expect(reading.caloriesPerContainer == 41_000)
    }

    @Test func theSecondNumberOnASingleColumnPanelIsIgnored() {
        // "servings per container" isn't a per-container column heading.
        let reading = NutritionLabelParser.read("3 servings per container\nCalories 100 5")
        #expect(reading.caloriesPerServing == 100)
        #expect(reading.caloriesPerContainer == nil)
    }

    @Test(arguments: [("3", 3.0), ("3.5", 3.5), (".5", 0.5), ("1/2", 0.5), ("3 1/2", 3.5)])
    func numbers(text: String, value: Double) {
        #expect(NutritionLabelParser.parseNumber(text).map { isApproximately($0, value) } == true)
    }
}
