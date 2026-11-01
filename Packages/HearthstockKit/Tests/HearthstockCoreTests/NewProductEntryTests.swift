import Foundation
import Testing
@testable import HearthstockCore

/// Slice 5 Tasks 5 and 7: one new product's draft, amount, calories and name guess, as the screens change them.
@Suite struct NewProductEntryTests {
    static let names = OpenFoodFactsTests.names
    static let profiles = OpenFoodFactsTests.profiles

    @Test func scannedCornWithServings() throws {
        let corn = try OpenFoodFactsTests.lookedUp("corn")
        let draft = try OpenFoodFactsTests.draft("corn")
        let guess = OpenFoodFacts.profileGuess(
            corn, categories: OpenFoodFactsTests.categories, names: Self.names, profiles: Self.profiles)
        var entry = NewProductEntry(draft: draft, amount: 1, lookedUp: corn, guess: guess)
        #expect(entry.naming.guess?.profile == "canned_low_acid")
        #expect(entry.calories.typedKcal == nil)
        entry.updateCalories { $0.servings = 3.5 }
        #expect(entry.draft.kcalPerBaseUnit == 280)
        #expect(try entry.draft.product().kcalPerBaseUnit == 280)
    }

    @Test func aDraftsOwnCaloriesStartAsTyped() {
        let typed = ProductDraft(name: "Beans", category: .food, unitKind: .count, kcalPerBaseUnit: 350)
        var entry = NewProductEntry(draft: typed, amount: 1)
        #expect(entry.calories.typedKcal == 350)
        entry.updateCalories { $0.label = NutritionReading(caloriesPerContainer: 400) }
        #expect(entry.draft.kcalPerBaseUnit == 350)
    }

    @Test func typingANotFoundName() {
        var entry = NewProductEntry(draft: ProductDraft(barcode: "0012345678905", category: .food, unitKind: .count))
        entry.setName("Brown rice", guesser: Self.names, profiles: Self.profiles)
        #expect(entry.draft.shelfLifeProfileKey == "brown_rice")
        entry.pickProfile("white_rice")
        entry.setName("Brown rice, 2 lb", guesser: Self.names, profiles: Self.profiles)
        #expect(entry.draft.shelfLifeProfileKey == "white_rice")
    }

    @Test func changingTheCategory() {
        var entry = NewProductEntry(draft: ProductDraft(category: .food, unitKind: .count), amount: 1)
        entry.setName("Corn", guesser: Self.names, profiles: Self.profiles)
        entry.updateCalories { $0.typedKcal = 280 }
        #expect(entry.draft.shelfLifeProfileKey == "canned_low_acid")

        entry.setCategory(.tools, guesser: Self.names, profiles: Self.profiles)
        #expect(entry.draft.kcalPerBaseUnit == nil)
        #expect(entry.draft.shelfLifeProfileKey == ProductDraft.defaultProfileKey(for: .tools))

        entry.setCategory(.food, guesser: Self.names, profiles: Self.profiles)
        #expect(entry.draft.kcalPerBaseUnit == 280)  // still the typed value
        #expect(entry.draft.shelfLifeProfileKey == "canned_low_acid")

        entry.setCategory(.water, guesser: Self.names, profiles: Self.profiles)
        #expect(entry.draft.shelfLifeProfileKey == "bottled_water")
    }

    @Test func aPickedProfileSurvivesACategoryRoundTripOnlyIfItIsntADefault() {
        var entry = NewProductEntry(draft: ProductDraft(category: .food, unitKind: .count))
        entry.pickProfile("flour")
        entry.setCategory(.other, guesser: Self.names, profiles: Self.profiles)
        #expect(entry.draft.shelfLifeProfileKey == "flour")
    }

    @Test func theFormsEditsWin() throws {
        let corn = try OpenFoodFactsTests.lookedUp("corn")
        var entry = NewProductEntry(draft: try OpenFoodFactsTests.draft("corn"), amount: 1, lookedUp: corn)
        var edited = entry.draft
        edited.name = "Corn"
        edited.kcalPerBaseUnit = 300
        edited.shelfLifeProfileKey = "canned_high_acid"
        entry.adopt(edited)
        #expect(entry.draft == edited)
        #expect(entry.naming.profilePicked)
        entry.updateCalories { $0.servings = 3.5 }
        #expect(entry.draft.kcalPerBaseUnit == 300)
        entry.setName("Sweet corn", guesser: Self.names, profiles: Self.profiles)
        #expect(entry.draft.shelfLifeProfileKey == "canned_high_acid")
    }

    @Test func riceSwitchesToPoundsFromItsNetWeight() throws {
        let rice = try OpenFoodFactsTests.lookedUp("rice-25lb")
        var entry = NewProductEntry(draft: try OpenFoodFactsTests.draft("rice-25lb"), amount: 1, lookedUp: rice)
        entry.updateCalories {
            $0.usesNetWeight = true
            $0.netWeight = Quantity(value: 25, unit: .pound)
        }
        #expect(entry.draft.unitKind == .mass)
        #expect(entry.amount == 25)
        #expect(entry.draft.kcalPerBaseUnit == 1641)
    }
}
