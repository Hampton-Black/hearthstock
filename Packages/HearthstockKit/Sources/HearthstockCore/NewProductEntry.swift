import Foundation

/// A new product being entered on the walk card, the add form or the not-found form (Slice 5 Tasks 5 and 7): its
/// draft and amount, the calorie answers and the name guess, kept in step. Each change goes through here so the three
/// screens behave alike.
public struct NewProductEntry: Hashable, Sendable {
    public var draft: ProductDraft
    /// The lot's amount as the screen holds it: items for a count product, else the entered amount. A Decision 8
    /// switch scales it (one 25 lb bag is 25 lb).
    public var amount: Double?
    public private(set) var calories: CalorieEntry
    public private(set) var naming: NameGuessing

    /// `guess` is the one the lookup's draft used (`OpenFoodFacts.profileGuess`), if any.
    public init(
        draft: ProductDraft, amount: Double? = nil, lookedUp: LookedUpProduct? = nil,
        guess: NameProfileGuesser.Guess? = nil
    ) {
        self.draft = draft
        self.amount = amount
        calories = CalorieEntry(lookedUp: lookedUp)
        naming = NameGuessing(guess: guess)
        calories.adopt(draft)
    }

    /// Changes the calorie answers and brings the draft (and amount) up to date.
    public mutating func updateCalories(_ change: (inout CalorieEntry) -> Void) {
        change(&calories)
        calories.apply(to: &draft, amount: &amount)
    }

    public mutating func setName(_ name: String, guesser: NameProfileGuesser, profiles: ShelfLifeProfileTable) {
        draft.name = name
        naming.nameChanged(&draft, guesser: guesser, profiles: profiles)
    }

    /// A profile still at the old category's default moves to the new one's; calories are kept only for food, and
    /// drinking water starts at the new category's default. The name is guessed again for the new category.
    public mutating func setCategory(
        _ category: Category, guesser: NameProfileGuesser, profiles: ShelfLifeProfileTable
    ) {
        let oldDefault = ProductDraft.defaultProfileKey(for: draft.category)
        draft.category = category
        if draft.shelfLifeProfileKey == oldDefault {
            draft.shelfLifeProfileKey = ProductDraft.defaultProfileKey(for: category)
        }
        draft.potableWaterGalPerBaseUnit = ProductDraft.defaultPotableWaterGalPerBaseUnit(
            category: category, unitKind: draft.unitKind)
        naming.nameChanged(&draft, guesser: guesser, profiles: profiles)
        if category == .food {
            calories.apply(to: &draft, amount: &amount)
        } else {
            draft.kcalPerBaseUnit = nil
        }
    }

    /// The person picked a profile ("Change"): the name no longer moves it.
    public mutating func pickProfile(_ key: ShelfLifeProfileKey) {
        naming.picked(key, in: &draft)
    }

    /// The draft as the product form handed it back: its fields win, its calories count as typed when they aren't
    /// the entry's own, and a profile it changed counts as picked.
    public mutating func adopt(_ edited: ProductDraft) {
        if edited.shelfLifeProfileKey != draft.shelfLifeProfileKey {
            naming.picked(edited.shelfLifeProfileKey, in: &draft)
        }
        let itemsBefore = calories.switchedUnitKind == nil ? nil : calories.itemsBeforeSwitch
        calories.adopt(edited)
        draft = edited
        // Put back to items by hand: the amount goes back too.
        if let itemsBefore, calories.switchedUnitKind == nil, edited.unitKind == .count { amount = itemsBefore }
    }
}
