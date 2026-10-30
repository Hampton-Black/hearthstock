import Foundation

/// What a Nutrition Facts panel says, as far as calories go. Any field may be missing. Never saved: the person
/// confirms it on the card or form first (Slice 5 Decision 4).
public struct NutritionReading: Hashable, Sendable {
    public var caloriesPerServing: Double?
    /// From a dual-column panel's per-container column.
    public var caloriesPerContainer: Double?
    public var servingsPerContainer: Double?
    /// "About 3.5 servings per container".
    public var servingsAreApproximate: Bool
    /// The household measure as printed: "1/2 cup", "1 can".
    public var servingSize: String?
    /// The serving's metric amount from the parentheses: "(125g)" is 125 g, "(240mL)" is 240 ml.
    public var servingQuantity: Quantity?
    /// "NET WT 15.25 OZ (432g)" is 15.25 oz, as printed first.
    public var netWeight: Quantity?

    public init(
        caloriesPerServing: Double? = nil, caloriesPerContainer: Double? = nil, servingsPerContainer: Double? = nil,
        servingsAreApproximate: Bool = false, servingSize: String? = nil, servingQuantity: Quantity? = nil,
        netWeight: Quantity? = nil
    ) {
        self.caloriesPerServing = caloriesPerServing
        self.caloriesPerContainer = caloriesPerContainer
        self.servingsPerContainer = servingsPerContainer
        self.servingsAreApproximate = servingsAreApproximate
        self.servingSize = servingSize
        self.servingQuantity = servingQuantity
        self.netWeight = netWeight
    }

    /// Nothing was read.
    public var isEmpty: Bool { self == NutritionReading() }
}

/// Reads the US FDA Nutrition Facts panel out of recognized text (Live Text): calories per serving (and per
/// container on dual-column panels), servings per container, the serving size and the net weight. Pure and
/// forgiving of Live Text's line breaks: "Servings per" and "container" on two lines, "Calories" in large type on a
/// line of its own with the number on the next.
///
/// Only "Calories" is read, never kJ "Energy". "Calories from Fat" (older panels) and the footnote's "Calories:
/// 2,000" are skipped, and a number followed by % is a Daily Value, never calories.
public enum NutritionLabelParser {
    public static func read(_ text: String) -> NutritionReading {
        let flat = normalized(text)
        var reading = NutritionReading()
        if let servings = servings(in: flat) {
            reading.servingsPerContainer = servings.value
            reading.servingsAreApproximate = servings.approximate
        }
        (reading.caloriesPerServing, reading.caloriesPerContainer) = calories(in: flat)
        (reading.servingSize, reading.servingQuantity) = servingSize(in: flat)
        reading.netWeight = netWeight(in: flat)
        return reading
    }

    /// One line, single spaces, unicode fractions as "1/2".
    static func normalized(_ text: String) -> String {
        var text = text
        for (glyph, ascii) in [("½", " 1/2"), ("⅓", " 1/3"), ("⅔", " 2/3"), ("¼", " 1/4"), ("¾", " 3/4"), ("⁄", "/")] {
            text = text.replacingOccurrences(of: glyph, with: ascii)
        }
        return text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    // MARK: Fields

    /// A number as panels print it: 3, 3.5, .5, 1/2, 3 1/2.
    private static let number = #"(?:\d+ \d+/\d+|\d+/\d+|\d*\.\d+|\d+)"#

    private static let servingsAfter = regex(#"(about|approx\.?|approximately|abt\.?)?\s*("# + number + #")\s+servings?\s+per\s+(?:container|package|pkg\.?|can|jar|bottle)"#)
    private static let servingsBefore = regex(#"servings?\s+per\s+(?:container|package|pkg\.?|can|jar|bottle)\s*:?\s*(about|approx\.?|approximately|abt\.?)?\s*("# + number + #")(?![\d/])"#)

    static func servings(in text: String) -> (value: Double, approximate: Bool)? {
        for pattern in [servingsAfter, servingsBefore] {
            guard let groups = firstMatch(pattern, in: text), let value = groups[2].flatMap(parseNumber), value > 0
            else { continue }
            return (value, groups[1] != nil)
        }
        return nil
    }

    /// "Calories 80" or "Calories per serving 210", with a second number on dual-column panels. Not "Calories from
    /// Fat", not "Calories: 2,000". A trailing comma ("Calories 200, Total Fat 6g") ends the number.
    private static let calorieNumber = #"(\d{1,3}(?:,\d{3})+|\d+)(?![\d%]|[,.]\d)"#
    private static let caloriesPattern = regex(#"\bcalories(?:\s+per\s+serving)?\s*"# + calorieNumber + #"(?:\s+"# + calorieNumber + #")?"#)
    /// A per-container column heading ("Per serving Per container"), not "2 servings per container" or "1 serving
    /// per container".
    private static let perContainerHeading = regex(#"(?<!servings )(?<!\d serving )\bper\s+(?:container|package|pkg\b|can\b|bottle\b)"#)
    /// The start of a column heading: "Per serving", "Per 1/2 Package", "Per 2.5oz dry mix". Not "servings per
    /// container" and not the single-column "Amount per serving".
    private static let headingStart = regex(#"(?<!servings )(?<!serving )(?<!amount )(?<!amount/)\bper\b"#)

    /// What a dual-column heading measures.
    enum Column: Equatable {
        case serving, container, prepared, other

        init(heading: String) {
            let heading = heading.lowercased()
            if heading.contains("prepared") {
                self = .prepared
            } else if heading.range(of: #"\bserving"#, options: .regularExpression) != nil {
                self = .serving
            } else if heading.range(of: #"^per\s+(?:container|package|pkg|can|bottle|box|bag)\b"#,
                                    options: .regularExpression) != nil {
                self = .container
            } else {
                self = .other
            }
        }
    }

    static func calories(in text: String) -> (perServing: Double?, perContainer: Double?) {
        let ns = text as NSString
        guard let match = caloriesPattern.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              let first = group(1, of: match, in: ns).flatMap(parseWhole)
        else { return (nil, nil) }
        guard let second = group(2, of: match, in: ns).flatMap(parseWhole) else { return (first, nil) }

        let headings = columnHeadings(before: match.range.location, in: ns)
        if headings.count == 2 {
            let columns = headings.map(Column.init(heading:))
            let values = [first, second]
            let container = columns.firstIndex(of: .container).map { values[$0] }
            // The serving column, else the first one that isn't "as prepared" (which adds what isn't in the box).
            let serving = columns.firstIndex(of: .serving) ?? columns.firstIndex { $0 != .prepared && $0 != .container }
            return (serving.map { values[$0] } ?? (container == nil ? first : nil), container)
        }
        let dualColumn = firstMatch(perContainerHeading, in: text) != nil
        return (first, dualColumn ? second : nil)
    }

    /// The last two column headings just before "Calories", in reading order. Each runs from its "Per" to the next
    /// heading or to "Calories", and a heading longer than a short phrase isn't a heading.
    private static func columnHeadings(before end: Int, in text: NSString) -> [String] {
        let starts = headingStart.matches(in: text as String, range: NSRange(location: 0, length: end))
            .map(\.range.location)
        let bounds = zip(starts, starts.dropFirst() + [end])
        let headings = bounds.map { text.substring(with: NSRange(location: $0, length: $1 - $0)) }
            .map { $0.trimmingCharacters(in: .whitespaces) }
        let lastTwo = Array(headings.suffix(2))
        guard lastTwo.count == 2, lastTwo.allSatisfy({ $0.count <= 30 }) else { return [] }
        return lastTwo
    }

    private static let servingWithMetric = regex(#"serv(?:ing|\.)?\s*size\s*:?\s*([^()]{0,40}?)\s*\(\s*(\d*\.?\d+)\s*(g|ml|l)\b"#)
    private static let servingPlain = regex(#"serv(?:ing|\.)?\s*size\s*:?\s*(.{1,30}?)(?=\s+(?:amount|servings?|calories|per|nutrition|%)\b|$)"#)

    static func servingSize(in text: String) -> (String?, Quantity?) {
        if let groups = firstMatch(servingWithMetric, in: text) {
            let household = groups[1].map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " ,:")) }
            let amount = groups[2].flatMap(Double.init)
            let unit: QuantityUnit? = switch groups[3]?.lowercased() {
            case "g": .gram
            case "ml": .milliliter
            case "l": .liter
            default: nil
            }
            let quantity = amount.flatMap { value in unit.map { Quantity(value: value, unit: $0) } }
            return (household?.isEmpty == false ? household : nil, quantity.flatMap { $0.value > 0 ? $0 : nil })
        }
        if let groups = firstMatch(servingPlain, in: text), let household = groups[1] {
            let trimmed = household.trimmingCharacters(in: CharacterSet(charactersIn: " ,:"))
            return (trimmed.isEmpty ? nil : trimmed, nil)
        }
        return (nil, nil)
    }

    /// "NET WT 15.25 OZ (432g)", "Net Wt. 1 LB 9 OZ", "NET CONTENTS 16.9 FL OZ (500 mL)", "NET 25 LB".
    private static let netPattern = regex(#"\bnet\s*(?:wt\.?|weight|contents?|quantity|qty\.?)?\s*:?\s*("# + number + #")\s*(fl\.?\s*oz\.?|oz\.?|lbs?\.?|pounds?|kg|g|ml|l|liters?|litres?|gal(?:lons?)?\.?)(?![a-z])(?:\s*(\d+(?:\.\d+)?)\s*oz\b)?"#)

    static func netWeight(in text: String) -> Quantity? {
        guard let groups = firstMatch(netPattern, in: text), let value = groups[1].flatMap(parseNumber), value > 0,
              let unitText = groups[2]
        else { return nil }
        let unit = unitText.lowercased().replacingOccurrences(of: ".", with: "").replacingOccurrences(of: " ", with: "")
        let quantityUnit: QuantityUnit
        switch unit {
        case "floz": quantityUnit = .fluidOunce
        case "oz": quantityUnit = .ounce
        case "lb", "lbs", "pound", "pounds": quantityUnit = .pound
        case "kg": quantityUnit = .kilogram
        case "g": quantityUnit = .gram
        case "ml": quantityUnit = .milliliter
        case "l", "liter", "liters", "litre", "litres": quantityUnit = .liter
        default: quantityUnit = .gallon
        }
        // "1 LB 9 OZ": the ounces add on.
        if quantityUnit == .pound, let ounces = groups[3].flatMap(Double.init) {
            return Quantity(value: value + ounces / 16, unit: .pound)
        }
        return Quantity(value: value, unit: quantityUnit)
    }

    // MARK: Pieces

    private static func regex(_ pattern: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }

    /// The first match's groups (index 0 is the whole match), nil for groups that didn't take part.
    private static func firstMatch(_ regex: NSRegularExpression, in text: String) -> [String?]? {
        let ns = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return (0..<match.numberOfRanges).map { index in
            let range = match.range(at: index)
            return range.location == NSNotFound ? nil : ns.substring(with: range)
        }
    }

    /// 3, 3.5, .5, 1/2, 3 1/2.
    static func parseNumber(_ text: String) -> Double? {
        let parts = text.split(separator: " ")
        var total = 0.0
        for part in parts {
            if let slash = part.firstIndex(of: "/") {
                guard let numerator = Double(part[..<slash]), let denominator = Double(part[part.index(after: slash)...]),
                      denominator > 0
                else { return nil }
                total += numerator / denominator
            } else {
                guard let value = Double(part) else { return nil }
                total += value
            }
        }
        return total.isFinite ? total : nil
    }

    private static func group(_ index: Int, of match: NSTextCheckingResult, in text: NSString) -> String? {
        let range = match.range(at: index)
        return range.location == NSNotFound ? nil : text.substring(with: range)
    }

    /// "1,630" → 1630.
    private static func parseWhole(_ text: String) -> Double? {
        Double(text.replacingOccurrences(of: ",", with: ""))
    }
}
