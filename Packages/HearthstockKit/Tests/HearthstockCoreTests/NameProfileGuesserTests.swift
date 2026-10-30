import Foundation
import Testing
@testable import HearthstockCore

/// Slice 5 Task 4: the profile guessed from a product's name.
@Suite struct NameProfileGuesserTests {
    static let profiles = try! ShelfLifeProfileTable.bundledDefaults()
    static let names = try! NameProfileGuesser.bundled()

    static func guess(_ name: String, size: String? = nil) -> NameProfileGuesser.Guess? {
        names.guess(name: name, quantityLabel: size, in: profiles)
    }

    @Test(arguments: [
        // Hampton's products.
        ("Whole Kernel Corn", "canned_low_acid"),
        ("H-E-B Whole Kernel Corn", "canned_low_acid"),
        ("Enriched Long Grain Parboiled Rice", "white_rice"),
        // Phrases before words.
        ("Brown Rice", "brown_rice"),
        ("Uncle Ben's Whole Grain BROWN RICE", "brown_rice"),
        ("Creamy Peanut Butter", "peanut_butter"),
        ("Pinto dried beans, 4 lb", "dried_beans"),
        ("Black Beans", "canned_low_acid"),
        ("Fruit Cocktail in Heavy Syrup", "canned_high_acid"),
        ("Traditional Spaghetti Sauce", "canned_high_acid"),
        ("Spaghetti", "pasta_dry"),
        ("Old Fashioned Rolled Oats", "rolled_oats"),
        ("All Purpose Flour", "flour"),
        ("Clover Honey", "honey_salt_sugar"),
        // Several matches take the shortest window: tomato (12) over soup (24).
        ("Tomato Soup", "canned_high_acid"),
        // Case and accents don't matter.
        ("PÊCHES and peaches", "canned_high_acid"),
        ("CHILI con carne", "canned_low_acid"),
    ])
    func guesses(name: String, profile: String) {
        #expect(Self.guess(name)?.profile == ShelfLifeProfileKey(rawValue: profile))
        #expect(Self.guess(name)?.category == .food)
    }

    @Test(arguments: [
        "Walmart Cinnamon rolls",
        "Cookies & Cream Pure Protein",
        "Black licorice",  // "rice" only as a whole word
        "Ricecakes",
        "Popcorn",
        "Honey Roasted Peanuts",  // a phrase that only stops "honey"
        "Honey Nut Cheerios",
        "",
        "  , ",
    ])
    func noGuess(name: String) {
        #expect(Self.guess(name) == nil)
    }

    @Test func waterIsWater() {
        let guess = Self.guess("Kirkland Signature Purified Drinking Water", size: "40 x 16.9 fl oz (500 ml)")
        #expect(guess == NameProfileGuesser.Guess(profile: "bottled_water", category: .water, phrase: "water"))
    }

    @Test func aFoodMatchBeatsWater() {
        #expect(Self.guess("Chunk Light Tuna in Water")?.category == .food)
        #expect(Self.guess("Chunk Light Tuna in Water")?.profile == "canned_low_acid")
        #expect(Self.guess("Water Chestnuts") == nil)
    }

    @Test func chickenNeedsACanCue() {
        #expect(Self.guess("Chicken breast") == nil)
        #expect(Self.guess("Chicken breast", size: "12.5 oz")?.profile == "canned_low_acid")
        #expect(Self.guess("Canned chicken breast")?.profile == "canned_low_acid")
        #expect(Self.guess("Chicken Noodle Soup")?.profile == "canned_low_acid")  // soup needs no cue
    }

    @Test func theGuessSaysWhichPhraseMatched() {
        #expect(Self.guess("Brown rice")?.phrase == "brown rice")
    }

    @Test func everyMappedProfileExists() {
        for keyword in Self.names.keywords {
            if let key = keyword.profile {
                #expect(Self.profiles[key] != nil, "\(keyword.phrase) → \(key)")
            }
        }
    }

    @Test func emptyGuessesNothing() {
        #expect(NameProfileGuesser.empty.guess(name: "Corn", in: Self.profiles) == nil)
    }

    @Test func aKeyMissingFromTheTableIsSkipped() throws {
        let guesser = NameProfileGuesser(keywords: [
            .init(phrase: "corn", profile: "no_such_profile"),
            .init(phrase: "sweet corn", profile: "canned_low_acid"),
        ])
        #expect(guesser.guess(name: "Corn", in: Self.profiles) == nil)
        #expect(guesser.guess(name: "Sweet corn", in: Self.profiles)?.profile == "canned_low_acid")
    }

    // MARK: In the draft

    @Test func theDraftUsesTheGuessOnlyWhenCategoriesSayNothing() throws {
        let corn = try OpenFoodFactsTests.lookedUp("corn")
        #expect(OpenFoodFacts.profileGuess(
            corn, categories: OpenFoodFactsTests.categories, names: Self.names, profiles: Self.profiles)?.phrase
            == "corn")
        // The soup's categories already say canned low acid: no guess shown.
        let soup = try OpenFoodFactsTests.lookedUp("campbells-soup")
        #expect(OpenFoodFacts.profileGuess(
            soup, categories: OpenFoodFactsTests.categories, names: Self.names, profiles: Self.profiles) == nil)
    }

    @Test func aWaterNameMakesAWaterDraft() {
        let water = LookedUpProduct(name: "Purified Drinking Water", quantityLabel: "1 gal", netQuantity: 3785.411784,
                                    netQuantityUnit: .millilitre)
        let draft = OpenFoodFacts.draft(
            from: water, barcode: nil, categories: OpenFoodFactsTests.categories, names: Self.names,
            profiles: Self.profiles)
        #expect(draft.category == .water)
        #expect(draft.shelfLifeProfileKey == "bottled_water")
        #expect(draft.potableWaterGalPerBaseUnit.map { isApproximately($0, 1) } == true)
        #expect(draft.kcalPerBaseUnit == nil)
    }
}
