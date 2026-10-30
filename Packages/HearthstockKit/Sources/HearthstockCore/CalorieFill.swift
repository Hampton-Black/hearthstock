import Foundation

/// Works out calories per base unit for a new product from what's known at the shelf (Slice 5 Decision 1): the
/// lookup, the person's answer to "servings per container" or "net weight", and a reading of the Nutrition Facts
/// panel. Pure: the card and form word the source.
public enum CalorieFill {
    /// How the calories were reached, in Decision 1's order.
    public enum Source: Hashable, Sendable {
        /// (a) The lookup's kcal per 100 g or ml, times the net quantity for an item (per lb or gal needs none).
        case netQuantity
        /// (b) A single-serving package ("1 bar"): its calories per serving.
        case singleServing
        /// (c) Calories per serving times the servings the person gave.
        case servings(kcalPerServing: Double, servings: Double)
        /// (d) The lookup's kcal per 100 times the net weight the person gave.
        case netWeight(kcalPer100: Double, netWeight: Quantity)
        /// (e) The Nutrition Facts panel.
        case label
    }

    public struct Fill: Hashable, Sendable {
        /// Rounded to whole kcal, as labels print them.
        public var value: Double
        public var source: Source

        public init(value: Double, source: Source) {
            self.value = value
            self.source = source
        }
    }

    /// Calories per base unit (per item, lb or gal), from the first rule that applies, or nil (missing nutrition,
    /// as before). Zero, negative or non-finite inputs are refused: that rule doesn't apply.
    ///
    /// Mass and volume products need only kcal per 100, so the person's answers and single servings are for count
    /// products; a label still helps them when the lookup had nothing.
    public static func kcalPerBaseUnit(
        lookedUp: LookedUpProduct?, unitKind: UnitKind, servingsPerContainer: Double? = nil,
        netWeight: Quantity? = nil, label: NutritionReading? = nil
    ) -> Fill? {
        let per100 = lookedUp?.kcalPer100.flatMap(nonNegative)
        let perServing = lookedUp?.kcalPerServing.flatMap(nonNegative)
        let servings = servingsPerContainer.flatMap(positive)
        let weight = netWeight.flatMap(validAmount)

        switch unitKind {
        case .energy:
            return nil
        case .mass, .volume:
            if let lookedUp, let value = OpenFoodFacts.kcalPerBaseUnit(lookedUp, unitKind: unitKind),
               let value = nonNegative(value)
            {
                return Fill(value: value.rounded(), source: .netQuantity)
            }
            return labelPerBaseUnit(label, lookedUp: lookedUp, unitKind: unitKind, servings: servings, netWeight: weight)
                .map { Fill(value: $0.rounded(), source: .label) }
        case .count:
            // (a)
            if let per100, let net = lookedUp?.netQuantity.flatMap(positive) {
                return Fill(value: (per100 * net / 100).rounded(), source: .netQuantity)
            }
            // (b)
            if let perServing, isSingleServing(lookedUp?.servingLabel) {
                return Fill(value: perServing.rounded(), source: .singleServing)
            }
            // (c)
            if let perServing, let servings {
                return Fill(
                    value: (perServing * servings).rounded(),
                    source: .servings(kcalPerServing: perServing, servings: servings))
            }
            // (d)
            if let per100, let weight, let amount = metric(weight)?.value {
                return Fill(value: (per100 * amount / 100).rounded(), source: .netWeight(kcalPer100: per100, netWeight: weight))
            }
            // (e)
            return labelPerItem(label, lookedUp: lookedUp, servings: servings, netWeight: weight)
                .map { Fill(value: $0.rounded(), source: .label) }
        }
    }

    /// Whether the card should ask for servings or a net weight: a count product whose lookup alone gives no
    /// calories. Mass and volume products never ask (Decision 2).
    public static func asksForServings(lookedUp: LookedUpProduct?, unitKind: UnitKind) -> Bool {
        unitKind == .count && kcalPerBaseUnit(lookedUp: lookedUp, unitKind: unitKind) == nil
    }

    /// "Net weight" is offered only when there's a kcal per 100 to multiply it by.
    public static func offersNetWeight(lookedUp: LookedUpProduct?) -> Bool {
        lookedUp?.kcalPer100.flatMap(nonNegative) != nil
    }

    // MARK: Single servings

    private static let singleServingUnits: Set<String> = [
        "bar", "can", "bottle", "pouch", "packet", "meal", "container",
    ]

    /// "1 bar", "1 can (340 g)", "1 Bottle": one of a package-sized unit. "2 rolls", "1/2 cup" and "1 cup" aren't.
    public static func isSingleServing(_ label: String?) -> Bool {
        guard let label else { return false }
        let words = label.lowercased().split { !$0.isLetter && !$0.isNumber && $0 != "/" && $0 != "." }
        guard words.count >= 2, words[0] == "1" else { return false }
        return singleServingUnits.contains(String(words[1]))
    }

    // MARK: The label

    /// Calories per item from a panel: per container when printed, else per serving × servings (the panel's, then
    /// the person's), else per serving × net weight ÷ serving amount when both are metric-comparable, else kcal per
    /// 100 × net weight. A partial reading is finished with the lookup: calories it didn't catch come from there.
    static func labelPerItem(
        _ label: NutritionReading?, lookedUp: LookedUpProduct? = nil, servings: Double?, netWeight: Quantity?
    ) -> Double? {
        guard let label else { return nil }
        if let perContainer = label.caloriesPerContainer.flatMap(nonNegative) { return perContainer }
        let perServing = (label.caloriesPerServing ?? lookedUp?.kcalPerServing).flatMap(nonNegative)
        if let perServing, let servings = label.servingsPerContainer.flatMap(positive) ?? servings {
            return perServing * servings
        }
        let net = (label.netWeight.flatMap(validAmount) ?? netWeight).flatMap(metric)
        let serving = label.servingQuantity.flatMap(validAmount).flatMap(metric)
        if let perServing, let net, let serving, net.kind == serving.kind, serving.value > 0 {
            return perServing * net.value / serving.value
        }
        if let per100 = lookedUp?.kcalPer100.flatMap(nonNegative), let net {
            return per100 * net.value / 100
        }
        return nil
    }

    /// Calories per lb or gal from a panel: per serving ÷ the serving's lb (or gal), else the panel's calories per
    /// item ÷ the net weight in lb (or gal), as when a bag's net weight switched it to mass (Decision 8).
    static func labelPerBaseUnit(
        _ label: NutritionReading?, lookedUp: LookedUpProduct? = nil, unitKind: UnitKind, servings: Double? = nil,
        netWeight: Quantity? = nil
    ) -> Double? {
        guard let label else { return nil }
        if let perServing = label.caloriesPerServing.flatMap(nonNegative),
           let serving = label.servingQuantity.flatMap(validAmount), serving.unit.kind == unitKind,
           let base = try? serving.inBaseUnit(), base.value > 0
        {
            return perServing / base.value
        }
        if let net = (label.netWeight.flatMap(validAmount) ?? netWeight), net.unit.kind == unitKind,
           let base = try? net.inBaseUnit(), base.value > 0,
           let perItem = labelPerItem(label, lookedUp: lookedUp, servings: servings, netWeight: net)
        {
            return perItem / base.value
        }
        return nil
    }

    // MARK: Pieces

    /// Grams for a mass, millilitres for a volume (kcal per 100 is per 100 g or per 100 ml).
    private static func metric(_ quantity: Quantity) -> (value: Double, kind: UnitKind)? {
        switch quantity.unit.kind {
        case .mass: (try? quantity.converted(to: .gram)).map { ($0.value, .mass) }
        case .volume: (try? quantity.converted(to: .milliliter)).map { ($0.value, .volume) }
        case .energy, .count: nil
        }
    }

    private static func validAmount(_ quantity: Quantity) -> Quantity? {
        quantity.value.isFinite && quantity.value > 0 ? quantity : nil
    }

    private static func positive(_ value: Double) -> Double? {
        value.isFinite && value > 0 ? value : nil
    }

    private static func nonNegative(_ value: Double) -> Double? {
        value.isFinite && value >= 0 ? value : nil
    }
}
