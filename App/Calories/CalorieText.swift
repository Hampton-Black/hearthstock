import Foundation
import HearthstockCore

/// How a new product's calories read on the walk card and the add forms (Slice 5 Task 5). Where a value came from
/// is shown only until the save (Decision 10).
enum CalorieText {
    /// "280 kcal per item"
    static func value(_ kcal: Double, unitKind: UnitKind) -> String {
        "\(Amount.kcal(kcal)) per \(unitKind.perUnit)"
    }

    /// "from Open Food Facts", "80 × 3.5 servings", "from the label"…
    static func origin(_ origin: CalorieEntry.Origin) -> String {
        switch origin {
        case .typed: "entered by you"
        case .filled(.netQuantity), .filled(.singleServing): "from Open Food Facts"
        case .filled(.servings(let perServing, let servings)):
            "\(Amount.text(perServing, fraction: 0)) × \(Amount.text(servings)) servings"
        case .filled(.netWeight(let per100, let net)):
            "\(Amount.text(per100, fraction: 0)) kcal per 100 \(net.unit.kind == .volume ? "ml" : "g") × \(QuantityText.format(net.value, net.unit))"
        case .filled(.label): "from the label"
        }
    }

    /// "80 kcal per serving (0.5 cup (125 g))", or the per-100 value when that's all Open Food Facts has.
    static func servingLine(_ lookedUp: LookedUpProduct?) -> String? {
        guard let lookedUp else { return nil }
        if let perServing = lookedUp.kcalPerServing {
            let size = lookedUp.servingLabel.map { " (\($0))" } ?? ""
            return "\(Amount.kcal(perServing)) per serving\(size)"
        }
        return lookedUp.kcalPer100.map { "\(Amount.kcal($0)) per 100 g" }
    }

    /// Decision 8's one-line note.
    static func switched(to kind: UnitKind) -> String {
        kind == .volume
            ? "Over 1 gal, so it's measured by volume now: calories are per gal."
            : "Over 2 lb, so it's measured by weight now: calories are per lb."
    }

    /// The Missing calories list's reason for one product.
    static func missing(_ reason: MissingCaloriesReason) -> String {
        switch reason {
        case .typedIn: "Typed in without calories"
        case .notLookedUp: "Not looked up online"
        case .notFound: "Open Food Facts doesn't know this barcode"
        case .noCaloriesOnline: "Open Food Facts had no calories for it"
        case .needsServings: "Open Food Facts had no package size: servings were skipped on the card"
        }
    }

    /// The label scan's live reading, one line per field read.
    static func reading(_ reading: NutritionReading) -> [String] {
        var lines: [String] = []
        if let perContainer = reading.caloriesPerContainer {
            lines.append("Calories \(Amount.text(perContainer, fraction: 0)) per container")
        }
        if let perServing = reading.caloriesPerServing {
            lines.append("Calories \(Amount.text(perServing, fraction: 0)) per serving")
        }
        if let servings = reading.servingsPerContainer {
            lines.append("\(reading.servingsAreApproximate ? "About " : "")\(Amount.text(servings)) servings per container")
        }
        if let size = reading.servingSize { lines.append("Serving size \(size)") }
        if let net = reading.netWeight { lines.append("Net Wt \(QuantityText.format(net.value, net.unit))") }
        return lines
    }
}
