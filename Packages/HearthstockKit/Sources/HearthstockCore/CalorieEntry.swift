import Foundation

/// The calories on a new product's walk card or add form (Slice 5 Task 5): what the lookup knew, the person's answer
/// to "Servings per container" or "Net weight", a Nutrition Facts reading, or calories they typed. Pure; the card
/// holds one and applies it to its draft after every change.
///
/// Nothing is guessed silently or over the person's own value: a typed value wins over every fill, and the fill says
/// where it came from (`Origin`).
public struct CalorieEntry: Hashable, Sendable {
    public var lookedUp: LookedUpProduct?
    public var servings: Double?
    public var netWeight: Quantity?
    /// The question is answered with a net weight instead of servings.
    public var usesNetWeight = false
    public var label: NutritionReading?
    /// kcal per base unit the person typed. No fill replaces it.
    public var typedKcal: Double?
    /// When a net weight switched a new count product to mass or volume (Decision 8): the kind, and the item count
    /// before, to scale the amount by and to go back to.
    public private(set) var switchedUnitKind: UnitKind?
    public private(set) var itemsBeforeSwitch: Double?
    /// One item's net weight in the switched base unit, so the amount is rescaled only when it changes and an
    /// amount typed after the switch is kept.
    private var switchedPerItem: Double?

    public init(lookedUp: LookedUpProduct? = nil) {
        self.lookedUp = lookedUp
    }

    /// Where the calories came from.
    public enum Origin: Hashable, Sendable {
        case typed
        case filled(CalorieFill.Source)
    }

    /// The net weight in play: the question's, else the label's.
    public var effectiveNetWeight: Quantity? {
        (usesNetWeight ? netWeight : nil) ?? label?.netWeight
    }

    /// Calories per base unit for `unitKind`, and where they came from; nil when nothing gives them.
    public func kcal(unitKind: UnitKind) -> (value: Double, origin: Origin)? {
        if let typedKcal { return (typedKcal, .typed) }
        let fill = CalorieFill.kcalPerBaseUnit(
            lookedUp: lookedUp, unitKind: unitKind, servingsPerContainer: usesNetWeight ? nil : servings,
            netWeight: usesNetWeight ? netWeight : nil, label: label)
        return fill.map { ($0.value, .filled($0.source)) }
    }

    /// The lookup has calories per serving, so "Servings per container" can answer.
    public var canAskServings: Bool {
        lookedUp?.kcalPerServing.map { $0.isFinite && $0 >= 0 } == true
    }

    /// The lookup has kcal per 100, so "Net weight" can answer.
    public var canAskNetWeight: Bool { CalorieFill.offersNetWeight(lookedUp: lookedUp) }

    /// Whether the card asks the question: a product counted by item (or switched from one by its net weight) whose
    /// lookup alone gives no calories, when an answer could give them, and the person hasn't typed their own.
    public func asksQuestion(unitKind: UnitKind) -> Bool {
        guard typedKcal == nil, unitKind == .count || switchedUnitKind != nil else { return false }
        return CalorieFill.asksForServings(lookedUp: lookedUp, unitKind: .count) && (canAskServings || canAskNetWeight)
    }

    /// Decision 8: over 2 lb is measured by mass, over 1 gal by volume (Slice 4 Decision 12's thresholds).
    public static func bulkUnitKind(for netWeight: Quantity) -> UnitKind? {
        guard netWeight.value.isFinite, netWeight.value > 0 else { return nil }
        switch netWeight.unit.kind {
        case .mass:
            guard let grams = try? netWeight.converted(to: .gram) else { return nil }
            return grams.value > OpenFoodFacts.bulkMassGrams ? .mass : nil
        case .volume:
            guard let ml = try? netWeight.converted(to: .milliliter) else { return nil }
            return ml.value > OpenFoodFacts.bulkVolumeMillilitres ? .volume : nil
        case .energy, .count:
            return nil
        }
    }

    /// Brings a new food product's draft up to date: switches it between items and mass or volume as the net weight
    /// crosses the threshold (scaling `amount`: one 25 lb bag is 25 lb), then sets its calories. Nothing else on
    /// the draft changes. Call it only before the product's first save: an existing product's unit kind never
    /// changes.
    public mutating func apply(to draft: inout ProductDraft, amount: inout Double?) {
        guard draft.category == .food else { return }
        if let net = effectiveNetWeight, let bulk = Self.bulkUnitKind(for: net),
           draft.unitKind == .count || switchedUnitKind != nil,
           let base = try? net.inBaseUnit()
        {
            if switchedUnitKind == nil { itemsBeforeSwitch = amount ?? 1 }
            if switchedUnitKind != bulk || switchedPerItem != base.value {
                amount = (itemsBeforeSwitch ?? 1) * base.value
            }
            switchedUnitKind = bulk
            switchedPerItem = base.value
            draft.unitKind = bulk
        } else if switchedUnitKind != nil {
            draft.unitKind = .count
            amount = itemsBeforeSwitch
            switchedUnitKind = nil
            itemsBeforeSwitch = nil
            switchedPerItem = nil
        }
        draft.kcalPerBaseUnit = kcal(unitKind: draft.unitKind)?.value
    }
}

extension CalorieEntry {
    /// A new product's draft as the product form handed it back: calories that aren't this entry's own count as
    /// typed, so no fill replaces them, and a unit kind changed by hand ends a Decision 8 switch.
    public mutating func adopt(_ draft: ProductDraft) {
        if let switched = switchedUnitKind, draft.unitKind != switched {
            switchedUnitKind = nil
            itemsBeforeSwitch = nil
            switchedPerItem = nil
        }
        guard draft.category == .food else { return }
        if draft.kcalPerBaseUnit != kcal(unitKind: draft.unitKind)?.value {
            typedKcal = draft.kcalPerBaseUnit
        }
    }
}

/// The profile a new product's typed name suggests (Slice 5 Decision 7): it follows the name while the profile is
/// still the category default or this guess, and stops for good once the person picks a profile.
public struct NameGuessing: Hashable, Sendable {
    public private(set) var guess: NameProfileGuesser.Guess?
    public private(set) var profilePicked = false

    /// `guess` is the one a lookup's draft already used (`OpenFoodFacts.profileGuess`), if any.
    public init(guess: NameProfileGuesser.Guess? = nil) {
        self.guess = guess
    }

    /// Guesses again from the draft's name (and size), for the draft's own category: a water guess doesn't turn a
    /// food draft into water, or the other way round.
    public mutating func nameChanged(
        _ draft: inout ProductDraft, guesser: NameProfileGuesser, profiles: ShelfLifeProfileTable
    ) {
        guard !profilePicked else { return }
        let fallback = ProductDraft.defaultProfileKey(for: draft.category)
        guard draft.shelfLifeProfileKey == fallback || draft.shelfLifeProfileKey == guess?.profile else {
            guess = nil
            return
        }
        let new = guesser.guess(name: draft.name, in: profiles).flatMap { $0.category == draft.category ? $0 : nil }
        guess = new
        draft.shelfLifeProfileKey = new?.profile ?? fallback
    }

    /// The person picked a profile: the name no longer moves it.
    public mutating func picked(_ key: ShelfLifeProfileKey, in draft: inout ProductDraft) {
        draft.shelfLifeProfileKey = key
        profilePicked = true
        guess = nil
    }
}
