import Foundation
import Testing
@testable import HearthstockCore

/// Slice 5 Tasks 5, 7 and 8: the card's calories, its name guess and the Missing calories reasons.
@Suite struct CalorieEntryTests {
    static func lookedUp(_ name: String) throws -> LookedUpProduct { try OpenFoodFactsTests.lookedUp(name) }

    static func draft(_ name: String) throws -> ProductDraft { try OpenFoodFactsTests.draft(name) }

    // MARK: Calories

    @Test func knownCaloriesAskNothing() throws {
        let bar = CalorieEntry(lookedUp: try Self.lookedUp("protein-bar"))
        #expect(!bar.asksQuestion(unitKind: .count))
        #expect(bar.kcal(unitKind: .count)?.value == 190)
        #expect(bar.kcal(unitKind: .count)?.origin == .filled(.singleServing))
    }

    @Test func cornAsksAndThreeAndAHalfServingsGive280() throws {
        var entry = CalorieEntry(lookedUp: try Self.lookedUp("corn"))
        #expect(entry.asksQuestion(unitKind: .count))
        #expect(entry.canAskServings)
        #expect(entry.canAskNetWeight)
        #expect(entry.kcal(unitKind: .count) == nil)

        var draft = try Self.draft("corn")
        var amount: Double? = 1
        entry.servings = 3.5
        entry.apply(to: &draft, amount: &amount)
        #expect(draft.kcalPerBaseUnit == 280)
        #expect(draft.unitKind == .count)
        #expect(amount == 1)
        #expect(entry.kcal(unitKind: .count)?.origin == .filled(.servings(kcalPerServing: 80, servings: 3.5)))
        #expect(entry.asksQuestion(unitKind: .count))  // the answer stays editable
    }

    @Test func skippingLeavesCaloriesEmpty() throws {
        var entry = CalorieEntry(lookedUp: try Self.lookedUp("corn"))
        var draft = try Self.draft("corn")
        var amount: Double? = 2
        entry.apply(to: &draft, amount: &amount)
        #expect(draft.kcalPerBaseUnit == nil)
        #expect(amount == 2)
    }

    @Test func servingsAreIgnoredWhileTheNetWeightAnswers() throws {
        var entry = CalorieEntry(lookedUp: try Self.lookedUp("corn"))
        entry.servings = 3.5
        entry.usesNetWeight = true
        entry.netWeight = Quantity(value: 15.25, unit: .ounce)
        #expect(entry.kcal(unitKind: .count)?.value == 277)
        entry.usesNetWeight = false
        #expect(entry.kcal(unitKind: .count)?.value == 280)
    }

    @Test func aTypedValueWinsOverEveryFill() throws {
        var entry = CalorieEntry(lookedUp: try Self.lookedUp("protein-bar"))
        entry.typedKcal = 200
        entry.label = NutritionReading(caloriesPerServing: 210, servingSize: "1 bar")
        var draft = try Self.draft("protein-bar")
        var amount: Double? = 1
        entry.apply(to: &draft, amount: &amount)
        #expect(draft.kcalPerBaseUnit == 200)
        #expect(entry.kcal(unitKind: .count)?.origin == .typed)
        #expect(!entry.asksQuestion(unitKind: .count))
    }

    @Test func aLabelReadingFillsWhenTheLookupCant() throws {
        var entry = CalorieEntry(lookedUp: nil)
        entry.label = NutritionReading(caloriesPerServing: 80, servingsPerContainer: 3.5, servingsAreApproximate: true)
        var draft = ProductDraft(name: "Corn", category: .food, unitKind: .count)
        var amount: Double? = 1
        entry.apply(to: &draft, amount: &amount)
        #expect(draft.kcalPerBaseUnit == 280)
        #expect(entry.kcal(unitKind: .count)?.origin == .filled(.label))
    }

    @Test func theProductFormsCaloriesCountAsTyped() throws {
        var entry = CalorieEntry(lookedUp: try Self.lookedUp("corn"))
        entry.servings = 3.5
        var draft = try Self.draft("corn")
        draft.kcalPerBaseUnit = 280
        entry.adopt(draft)  // the form left the filled value alone
        #expect(entry.typedKcal == nil)
        draft.kcalPerBaseUnit = 300
        entry.adopt(draft)
        #expect(entry.typedKcal == 300)
        entry.servings = 4
        var amount: Double? = 1
        entry.apply(to: &draft, amount: &amount)
        #expect(draft.kcalPerBaseUnit == 300)
    }

    @Test func aUnitKindChangedByHandEndsTheSwitch() throws {
        var entry = CalorieEntry(lookedUp: try Self.lookedUp("rice-25lb"))
        var draft = try Self.draft("rice-25lb")
        var amount: Double? = 1
        entry.usesNetWeight = true
        entry.netWeight = Quantity(value: 25, unit: .pound)
        entry.apply(to: &draft, amount: &amount)
        #expect(draft.unitKind == .mass)
        draft.unitKind = .count
        entry.adopt(draft)
        #expect(entry.switchedUnitKind == nil)
    }

    // MARK: Decision 8

    @Test func aBulkNetWeightSwitchesToMassAndBack() throws {
        var entry = CalorieEntry(lookedUp: try Self.lookedUp("rice-25lb"))
        var draft = try Self.draft("rice-25lb")
        #expect(draft.unitKind == .count)
        var amount: Double? = 2
        entry.usesNetWeight = true
        entry.netWeight = Quantity(value: 25, unit: .pound)
        entry.apply(to: &draft, amount: &amount)
        #expect(draft.unitKind == .mass)
        #expect(entry.switchedUnitKind == .mass)
        #expect(amount.map { isApproximately($0, 50) } == true)  // two 25 lb bags
        #expect(draft.kcalPerBaseUnit == 1641)  // per lb
        #expect(entry.asksQuestion(unitKind: .mass))  // still there, to undo the switch

        // A smaller weight goes back to two bags, and their calories.
        entry.netWeight = Quantity(value: 2, unit: .pound)
        entry.apply(to: &draft, amount: &amount)
        #expect(draft.unitKind == .count)
        #expect(entry.switchedUnitKind == nil)
        #expect(amount == 2)
        #expect(draft.kcalPerBaseUnit == 3281)  // 361.7 × 907.18 g ÷ 100

        // Turning the net weight off also undoes it.
        entry.netWeight = Quantity(value: 25, unit: .pound)
        entry.apply(to: &draft, amount: &amount)
        #expect(draft.unitKind == .mass)
        entry.usesNetWeight = false
        entry.apply(to: &draft, amount: &amount)
        #expect(draft.unitKind == .count)
        #expect(amount == 2)
    }

    @Test func anAmountTypedAfterTheSwitchIsKept() throws {
        var entry = CalorieEntry(lookedUp: try Self.lookedUp("rice-25lb"))
        var draft = try Self.draft("rice-25lb")
        var amount: Double? = 1
        entry.usesNetWeight = true
        entry.netWeight = Quantity(value: 25, unit: .pound)
        entry.apply(to: &draft, amount: &amount)
        #expect(amount == 25)
        amount = 50  // typed by hand: a bag and a half
        entry.servings = 3  // an unrelated change
        entry.apply(to: &draft, amount: &amount)
        #expect(amount == 50)
        entry.netWeight = Quantity(value: 20, unit: .pound)  // a new net weight rescales the item count
        entry.apply(to: &draft, amount: &amount)
        #expect(amount == 20)
    }

    @Test func aLabelsNetWeightSwitchesToo() throws {
        var entry = CalorieEntry(lookedUp: nil)
        entry.label = NutritionReading(
            caloriesPerServing: 160, servingsPerContainer: 180, netWeight: Quantity(value: 20, unit: .pound))
        var draft = ProductDraft(name: "Rice", category: .food, unitKind: .count)
        var amount: Double? = 1
        entry.apply(to: &draft, amount: &amount)
        #expect(draft.unitKind == .mass)
        #expect(amount == 20)
        #expect(draft.kcalPerBaseUnit == 1440)  // 160 × 180 ÷ 20 lb
    }

    @Test func aDraftAlreadyByMassIsNeverSwitchedToCount() throws {
        var entry = CalorieEntry(lookedUp: try Self.lookedUp("derived-rice-25lb-with-size"))
        var draft = try Self.draft("derived-rice-25lb-with-size")
        var amount: Double? = 25
        entry.usesNetWeight = true
        entry.netWeight = Quantity(value: 1, unit: .pound)
        entry.apply(to: &draft, amount: &amount)
        #expect(draft.unitKind == .mass)
        #expect(amount == 25)
    }

    @Test func waterIsLeftAlone() throws {
        var entry = CalorieEntry(lookedUp: try Self.lookedUp("derived-water-named"))
        entry.typedKcal = 5
        var draft = try Self.draft("derived-water-named")
        let before = draft
        var amount: Double? = 40
        entry.apply(to: &draft, amount: &amount)
        #expect(draft == before)
        #expect(amount == 40)
    }

    @Test(arguments: [
        (Quantity(value: 2, unit: .pound), nil as UnitKind?),
        (Quantity(value: 2.01, unit: .pound), .mass),
        (Quantity(value: 1, unit: .kilogram), .mass),
        (Quantity(value: 15.25, unit: .ounce), nil),
        (Quantity(value: 1, unit: .gallon), nil),
        (Quantity(value: 4, unit: .liter), .volume),
        (Quantity(value: 128, unit: .fluidOunce), nil),
        (Quantity(value: 0, unit: .pound), nil),
    ] as [(Quantity, UnitKind?)])
    func bulkThresholds(net: Quantity, kind: UnitKind?) {
        #expect(CalorieEntry.bulkUnitKind(for: net) == kind)
    }

    // MARK: Name guess (Decision 7)

    static let names = OpenFoodFactsTests.names
    static let profiles = OpenFoodFactsTests.profiles

    @Test func typedNamesAreGuessedUntilAProfileIsPicked() {
        var draft = ProductDraft(category: .food, unitKind: .count)
        var guessing = NameGuessing()
        for (name, profile) in [
            ("B", "unknown_food"), ("Brown", "unknown_food"), ("Brown rice", "brown_rice"),
            ("Brown rice cakes", "unknown_food"), ("Crackers", "unknown_food"), ("Corn", "canned_low_acid"),
        ] as [(String, ShelfLifeProfileKey)] {
            draft.name = name
            guessing.nameChanged(&draft, guesser: Self.names, profiles: Self.profiles)
            #expect(draft.shelfLifeProfileKey == profile, "\(name)")
        }
        #expect(guessing.guess?.phrase == "corn")

        guessing.picked("flour", in: &draft)
        draft.name = "Brown rice"
        guessing.nameChanged(&draft, guesser: Self.names, profiles: Self.profiles)
        #expect(draft.shelfLifeProfileKey == "flour")
        #expect(guessing.guess == nil)
    }

    @Test func aProfileThatIsntTheDefaultOrTheGuessIsKept() {
        var draft = ProductDraft(name: "", category: .food, unitKind: .count, shelfLifeProfileKey: "flour")
        var guessing = NameGuessing()
        draft.name = "Rice"
        guessing.nameChanged(&draft, guesser: Self.names, profiles: Self.profiles)
        #expect(draft.shelfLifeProfileKey == "flour")
    }

    @Test func aGuessForAnotherCategoryIsIgnored() {
        var draft = ProductDraft(category: .food, unitKind: .count)
        var guessing = NameGuessing()
        draft.name = "Spring water"
        guessing.nameChanged(&draft, guesser: Self.names, profiles: Self.profiles)
        #expect(draft.shelfLifeProfileKey == "unknown_food")
        #expect(guessing.guess == nil)

        var water = ProductDraft(category: .water, unitKind: .count)
        water.name = "Spring water"
        guessing.nameChanged(&water, guesser: Self.names, profiles: Self.profiles)
        #expect(water.shelfLifeProfileKey == "bottled_water")
        #expect(guessing.guess?.category == .water)
    }

    @Test func theLookupsGuessCarriesOver() throws {
        let corn = try Self.lookedUp("corn")
        let guess = OpenFoodFacts.profileGuess(
            corn, categories: OpenFoodFactsTests.categories, names: Self.names, profiles: Self.profiles)
        #expect(guess?.profile == "canned_low_acid")
        var draft = try Self.draft("corn")
        var guessing = NameGuessing(guess: guess)
        draft.name = "H-E-B Whole Kernel Corn, 15.25 oz"
        guessing.nameChanged(&draft, guesser: Self.names, profiles: Self.profiles)
        #expect(draft.shelfLifeProfileKey == "canned_low_acid")
    }

    // MARK: Missing calories (Task 8)

    @Test func reasons() throws {
        func product(barcode: String?) -> Product {
            Product(
                name: "Corn", barcode: barcode, category: .food, role: .supply, unitKind: .count,
                shelfLifeProfileKey: "canned_low_acid")
        }
        let code = try Barcode("0041220156726")
        func cached(_ outcome: CachedLookup.Outcome) -> CachedLookup {
            CachedLookup(barcode: code, outcome: outcome, fetchedAt: Date(timeIntervalSinceReferenceDate: 0))
        }
        #expect(MissingCaloriesReason.reason(for: product(barcode: nil), cached: nil) == .typedIn)
        let scanned = product(barcode: code.rawValue)
        #expect(MissingCaloriesReason.reason(for: scanned, cached: nil) == .notLookedUp)
        #expect(MissingCaloriesReason.reason(for: scanned, cached: cached(.notFound)) == .notFound)
        #expect(MissingCaloriesReason.reason(for: scanned, cached: cached(.found(try Self.lookedUp("corn"))))
            == .needsServings)
        #expect(MissingCaloriesReason.reason(for: scanned, cached: cached(.found(try Self.lookedUp("water-40pack"))))
            == .noCaloriesOnline)
    }

    @Test func walkCountsFoodStillMissingCalories() {
        let corn = Product(name: "Corn", category: .food, role: .supply, unitKind: .count,
                           shelfLifeProfileKey: "canned_low_acid")
        let soup = Product(name: "Soup", category: .food, role: .supply, unitKind: .count, kcalPerBaseUnit: 248,
                           shelfLifeProfileKey: "canned_low_acid")
        let water = Product(name: "Water", category: .water, role: .supply, unitKind: .count,
                            shelfLifeProfileKey: "bottled_water")
        let gone = ProductID()
        var walk = PantryWalk(locationID: LocationID(), startedAt: Date(timeIntervalSinceReferenceDate: 0))
        walk.record(.createdProductAndLot(LotID(), product: corn.id, amount: 1, date: .printed))
        walk.record(.createdProductAndLot(LotID(), product: soup.id, amount: 1, date: .printed))
        walk.record(.createdProductAndLot(LotID(), product: water.id, amount: 1, date: .notNeeded))
        walk.record(.createdLot(LotID(), product: gone, amount: 1, date: .printed))
        walk.record(.createdLot(LotID(), product: corn.id, amount: 1, date: .printed))
        #expect(walk.productsMissingCalories([corn, soup, water]) == [corn.id])

        var fixed = corn
        fixed.kcalPerBaseUnit = 280
        #expect(walk.productsMissingCalories([fixed, soup, water]).isEmpty)
    }

    // MARK: Live Text frames

    @Test func readingsMergeFrameByFrame() {
        let first = NutritionReading(caloriesPerServing: 80, servingsPerContainer: 3.5, servingsAreApproximate: true)
        let second = NutritionReading(
            servingsPerContainer: 4, servingSize: "1/2 cup", netWeight: Quantity(value: 15.25, unit: .ounce))
        let merged = first.merging(second)
        #expect(merged.caloriesPerServing == 80)
        #expect(merged.servingsPerContainer == 4)
        #expect(!merged.servingsAreApproximate)
        #expect(merged.servingSize == "1/2 cup")
        #expect(merged.netWeight == Quantity(value: 15.25, unit: .ounce))
        #expect(first.merging(NutritionReading()) == first)
    }
}

/// The Slice 5 review's fixes.
@Suite struct CalorieEntryReviewTests {
    static let corn = LookedUpProduct(name: "Corn", kcalPer100: 64, kcalPerServing: 80, servingLabel: "0.5 cup (125 g)")
    static let profiles = try! ShelfLifeProfileTable.bundledDefaults()
    static let categories = try! OFFCategoryMap.bundled()
    static let names = try! NameProfileGuesser.bundled()

    static func draft(_ product: LookedUpProduct) -> ProductDraft {
        OpenFoodFacts.draft(from: product, barcode: nil, categories: categories, names: names, profiles: profiles)
    }

    @Test func aPartialReadingIsFinishedWithTheLookup() {
        var servingsOnly = CalorieEntry(lookedUp: Self.corn)
        servingsOnly.label = NutritionReading(servingsPerContainer: 3.5)
        #expect(servingsOnly.kcal(unitKind: .count)?.value == 280)

        var netOnly = CalorieEntry(lookedUp: Self.corn)
        netOnly.label = NutritionReading(netWeight: Quantity(value: 100, unit: .gram))
        #expect(netOnly.kcal(unitKind: .count)?.value == 64)
        #expect(netOnly.kcal(unitKind: .count)?.origin == .filled(.label))
    }

    @Test func aReadingWithNothingToFinishItStaysEmpty() {
        var entry = CalorieEntry()
        entry.label = NutritionReading(servingsPerContainer: 3.5)
        #expect(entry.kcal(unitKind: .count) == nil)
    }

    @Test func usingALabelReplacesTheAnswers() {
        var entry = CalorieEntry(lookedUp: Self.corn)
        entry.servings = 3
        entry.typedKcal = 300
        entry.useLabel(NutritionReading(caloriesPerServing: 80, servingsPerContainer: 3.5))
        #expect(entry.kcal(unitKind: .count)?.value == 280)
    }

    @Test func clearedCaloriesStayEmptyUntilAnswered() {
        let bar = LookedUpProduct(name: "Bar", kcalPerServing: 190, servingLabel: "1 bar (50 g)")
        var entry = NewProductEntry(draft: Self.draft(bar), amount: 1, lookedUp: bar)
        var edited = entry.draft
        edited.kcalPerBaseUnit = nil
        entry.adopt(edited)
        #expect(entry.draft.kcalPerBaseUnit == nil)
        #expect(entry.calories.kcal(unitKind: .count) == nil)
        entry.updateCalories { $0.typedKcal = 200 }
        #expect(entry.draft.kcalPerBaseUnit == 200)
    }

    @Test func aSwitchPutBackByHandStaysBack() {
        let rice = LookedUpProduct(name: "Rice", kcalPer100: 362, kcalPerServing: 170)
        var entry = NewProductEntry(draft: Self.draft(rice), amount: 1, lookedUp: rice)
        entry.updateCalories {
            $0.usesNetWeight = true
            $0.netWeight = Quantity(value: 25, unit: .pound)
        }
        #expect(entry.draft.unitKind == .mass)
        var back = entry.draft
        back.unitKind = .count
        entry.adopt(back)
        #expect(entry.amount == 1)
        entry.updateCalories { $0.servings = 2 }
        #expect(entry.draft.unitKind == .count)
        #expect(entry.amount == 1)
    }

    @Test(arguments: ["Corn Flakes, 12 oz", "Chicken Nuggets, 32 oz", "Rice Krispies", "Frozen Corn", "Water Crackers"])
    func notEverythingNamedLikeACanIsOne(name: String) {
        #expect(Self.names.guess(name: name, in: Self.profiles) == nil)
    }

    @Test func somethingWithCaloriesIsntWater() {
        let drink = LookedUpProduct(name: "Coconut Water", kcalPer100: 19)
        let draft = Self.draft(drink)
        #expect(draft.category == .food)
        #expect(draft.kcalPerBaseUnit == nil || draft.kcalPerBaseUnit! > 0)
    }
}
