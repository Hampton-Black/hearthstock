import Foundation

/// Open Food Facts category tags mapped to shelf-life profiles and to water, from the bundled
/// `off-category-profiles.json`. Data, not code, like the shelf-life table.
public struct OFFCategoryMap: Hashable, Sendable {
    public let profiles: [String: ShelfLifeProfileKey]
    public let waterTags: Set<String>

    public init(profiles: [String: ShelfLifeProfileKey], waterTags: Set<String>) {
        self.profiles = profiles
        self.waterTags = waterTags
    }

    private struct File: Decodable {
        var profiles: [String: ShelfLifeProfileKey]
        var waterTags: [String]
    }

    public init(jsonData: Data) throws {
        let file = try JSONDecoder().decode(File.self, from: jsonData)
        self.init(profiles: file.profiles, waterTags: Set(file.waterTags))
    }

    public enum LoadError: Error, Equatable, CustomStringConvertible {
        case missingResource

        public var description: String { "off-category-profiles.json isn't in the app bundle" }
    }

    /// No category guesses: every looked-up product starts on its category's default profile.
    public static let empty = OFFCategoryMap(profiles: [:], waterTags: [])

    public static func bundled() throws -> OFFCategoryMap {
        guard let url = Bundle.module.url(forResource: "off-category-profiles", withExtension: "json") else {
            throw LoadError.missingResource
        }
        return try OFFCategoryMap(jsonData: Data(contentsOf: url))
    }

    public func isWater(_ tags: [String]) -> Bool {
        tags.contains { waterTags.contains($0) }
    }

    /// The matching profile with the shortest window (the conservative guess), or nil when no tag matches a profile
    /// in `table`. Ties go by key.
    public func profile(for tags: [String], in table: ShelfLifeProfileTable) -> ShelfLifeProfileKey? {
        let candidates = Set(tags.compactMap { profiles[$0] }).compactMap { table[$0] }
        return candidates.min { lhs, rhs in
            let l = Self.windowMonths(lhs), r = Self.windowMonths(rhs)
            return l != r ? l < r : lhs.key.rawValue < rhs.key.rawValue
        }?.key
    }

    /// Months of use a profile allows past its start: the extension for best-by, none for use-by, the rotation for
    /// date type none (unlimited without one).
    static func windowMonths(_ profile: ShelfLifeProfile) -> Int {
        switch profile.dateType {
        case .bestBy: profile.extensionMonths ?? 0
        case .useBy: 0
        case .none: profile.rotationMonths ?? .max
        }
    }
}

/// Reading Open Food Facts v3 product responses and turning them into drafts. Pure: the network call lives in
/// HearthstockLookup, which hands the body and status code to `decode`.
public enum OpenFoodFacts {
    static let gramsPerPound = 453.59237
    static let millilitresPerGallon = 3785.411784
    static let kilojoulesPerKilocalorie = 4.184
    /// Decision 12: over 2 lb is bulk, measured by mass.
    static let bulkMassGrams = 2 * gramsPerPound
    /// Decision 12: over 1 gal is bulk, measured by volume.
    static let bulkVolumeMillilitres = millilitresPerGallon

    // MARK: Decoding

    /// The answer a response gives. 404 (and a 3xx redirect to a sister database, for non-food items) is not found;
    /// 429 is rate limited; any other failure, or a 200 that isn't readable JSON, is a server error.
    public static func decode(_ data: Data, httpStatus: Int) -> LookupResult {
        switch httpStatus {
        case 200: break
        case 404, 300..<400: return .notFound
        case 429: return .unavailable(.rateLimited)
        default: return .unavailable(.serverError)
        }
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return .unavailable(.serverError)
        }
        if (root["result"] as? [String: Any])?["id"] as? String == "product_not_found" { return .notFound }
        guard let product = root["product"] as? [String: Any] else { return .notFound }
        return .found(lookedUpProduct(product))
    }

    /// Every field is optional: a missing or malformed one is left empty, never failing the lookup.
    static func lookedUpProduct(_ product: [String: Any]) -> LookedUpProduct {
        let nutriments = product["nutriments"] as? [String: Any] ?? [:]
        let kcal = number(nutriments["energy-kcal_100g"]) ?? number(nutriments["energy-kcal_100ml"])
            ?? (number(nutriments["energy-kj_100g"]) ?? number(nutriments["energy-kj_100ml"]))
                .map { $0 / kilojoulesPerKilocalorie }
        let net = netQuantity(number(product["product_quantity"]), unit: text(product["product_quantity_unit"]))
        let serving = netQuantity(number(product["serving_quantity"]), unit: text(product["serving_quantity_unit"]))
        let brand = text(product["brands"])?.split(separator: ",").first
            .map { $0.trimmingCharacters(in: .whitespaces) }
        return LookedUpProduct(
            name: text(product["product_name"]) ?? text(product["product_name_en"]),
            brand: brand?.isEmpty == false ? brand : nil,
            quantityLabel: text(product["quantity"]),
            netQuantity: net?.value,
            netQuantityUnit: net?.unit,
            kcalPer100: kcal,
            kcalPerServing: number(nutriments["energy-kcal_serving"]),
            servingLabel: text(product["serving_size"]),
            servingQuantity: serving?.value,
            servingQuantityUnit: serving?.unit,
            categoryTags: product["categories_tags"] as? [String] ?? [])
    }

    private static func netQuantity(_ value: Double?, unit: String?) -> (value: Double, unit: LookedUpProduct.NetUnit)? {
        guard let value, value > 0, let unit = unit?.lowercased() else { return nil }
        switch unit {
        case "g": return (value, .gram)
        case "kg": return (value * 1000, .gram)
        case "ml": return (value, .millilitre)
        case "cl": return (value * 10, .millilitre)
        case "l": return (value * 1000, .millilitre)
        default: return nil
        }
    }

    /// A finite number from a JSON number or a numeric string.
    private static func number(_ value: Any?) -> Double? {
        let result: Double? = switch value {
        case let number as NSNumber: number.doubleValue
        case let string as String: Double(string.trimmingCharacters(in: .whitespaces))
        default: nil
        }
        return result.flatMap { $0.isFinite ? $0 : nil }
    }

    /// A trimmed, non-empty string.
    private static func text(_ value: Any?) -> String? {
        guard let string = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !string.isEmpty
        else { return nil }
        return string
    }

    // MARK: Drafts

    /// The add form's starting point for a found product. Everything stays editable before the first save.
    ///
    /// The profile comes from the categories, then from the name when they say nothing (Slice 5 Decision 6), then
    /// the category default.
    public static func draft(
        from product: LookedUpProduct, barcode: Barcode?, categories: OFFCategoryMap, names: NameProfileGuesser,
        profiles: ShelfLifeProfileTable
    ) -> ProductDraft {
        let guess = profileGuess(product, categories: categories, names: names, profiles: profiles)
        let category: Category = categories.isWater(product.categoryTags) ? .water : guess?.category ?? .food
        let kind = unitKind(product)
        return ProductDraft(
            name: name(product),
            barcode: barcode?.rawValue,
            category: category,
            unitKind: kind,
            kcalPerBaseUnit: category == .food ? suggestedKcal(product, unitKind: kind) : nil,
            potableWaterGalPerBaseUnit: category == .water ? suggestedWaterGal(product, unitKind: kind) : nil,
            shelfLifeProfileKey: categories.profile(for: product.categoryTags, in: profiles) ?? guess?.profile
                ?? ProductDraft.defaultProfileKey(for: category))
    }

    /// The name's guess when the categories give neither water nor a profile, else nil: what the draft's profile
    /// was "guessed from the name", for the card and form to say so.
    public static func profileGuess(
        _ product: LookedUpProduct, categories: OFFCategoryMap, names: NameProfileGuesser,
        profiles: ShelfLifeProfileTable
    ) -> NameProfileGuesser.Guess? {
        guard !categories.isWater(product.categoryTags),
              categories.profile(for: product.categoryTags, in: profiles) == nil,
              let name = product.name
        else { return nil }
        let guess = names.guess(name: name, quantityLabel: product.quantityLabel, in: profiles)
        // Something with calories isn't water, whatever its name says ("Water Crackers", "Coconut Water").
        let hasCalories = (product.kcalPer100 ?? 0) > 0 || (product.kcalPerServing ?? 0) > 0
        return guess?.category == .water && hasCalories ? nil : guess
    }

    /// Brand, product name and the label's size, because different sizes are different products: "Campbell's Cream
    /// Of Mushroom Soup, 10.5 oz". The brand and size are left out when the name already contains them.
    public static func name(_ product: LookedUpProduct) -> String {
        var name = product.name ?? ""
        if let brand = product.brand, !name.localizedCaseInsensitiveContains(brand) {
            name = name.isEmpty ? brand : "\(brand) \(name)"
        }
        if !name.isEmpty, let size = sizeLabel(product.quantityLabel), !name.localizedCaseInsensitiveContains(size) {
            name += ", \(size)"
        }
        return name
    }

    /// "10.5 oz (298 g)" → "10.5 oz".
    static func sizeLabel(_ label: String?) -> String? {
        guard let label else { return nil }
        let first = label.components(separatedBy: " (").first?.trimmingCharacters(in: .whitespaces) ?? ""
        return first.isEmpty ? nil : first
    }

    /// Decision 12: over 2 lb net is mass, over 1 gal is volume, anything smaller (or unknown) is count, one item per
    /// can, jar or bottle.
    public static func unitKind(_ product: LookedUpProduct) -> UnitKind {
        guard let net = product.netQuantity, let unit = product.netQuantityUnit else { return .count }
        switch unit {
        case .gram: return net > bulkMassGrams ? .mass : .count
        case .millilitre: return net > bulkVolumeMillilitres ? .volume : .count
        }
    }

    /// Calories per base unit for `unitKind`: per lb or per gal from the per-100 value, per item only when the net
    /// quantity is known. Never from a serving: `CalorieFill` adds single servings and the person's answers.
    public static func kcalPerBaseUnit(_ product: LookedUpProduct, unitKind: UnitKind) -> Double? {
        guard let per100 = product.kcalPer100 else { return nil }
        switch unitKind {
        case .mass: return per100 * gramsPerPound / 100
        case .volume: return per100 * millilitresPerGallon / 100
        case .count:
            guard let net = product.netQuantity else { return nil }
            return per100 * net / 100
        case .energy: return nil
        }
    }

    /// What a form starts with: calories rounded to whole kcal, as labels print them, and drinkable water to a
    /// thousandth of a gallon. Calories come from the lookup alone (`CalorieFill` rules a and b): per 100 × net
    /// quantity, or a single-serving package's calories per serving.
    public static func suggestedKcal(_ product: LookedUpProduct, unitKind: UnitKind) -> Double? {
        CalorieFill.kcalPerBaseUnit(lookedUp: product, unitKind: unitKind)?.value
    }

    public static func suggestedWaterGal(_ product: LookedUpProduct, unitKind: UnitKind) -> Double? {
        potableWaterGalPerBaseUnit(product, unitKind: unitKind).map { ($0 * 1000).rounded() / 1000 }
    }

    /// Drinkable gallons per base unit for a water product: 1 per gallon, or the bottle's size per item.
    public static func potableWaterGalPerBaseUnit(_ product: LookedUpProduct, unitKind: UnitKind) -> Double? {
        switch unitKind {
        case .volume: return 1
        case .count:
            guard let net = product.netQuantity, product.netQuantityUnit == .millilitre else { return nil }
            return net / millilitresPerGallon
        case .mass, .energy: return nil
        }
    }
}

extension ProductDraft {
    /// A field a lookup can fill in.
    public enum FilledField: Hashable, Sendable, CaseIterable {
        case name
        case calories
        case water
    }

    /// This draft with only its empty fields filled from `product`, and which were filled. Nothing the user
    /// entered changes (spec): category, unit kind and profile are never touched, and calories and water are
    /// computed for this draft's own unit kind.
    public func fillingEmptyFields(from product: LookedUpProduct) -> (draft: ProductDraft, filled: Set<FilledField>) {
        var draft = self
        var filled: Set<FilledField> = []
        let name = OpenFoodFacts.name(product)
        if draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !name.isEmpty {
            draft.name = name
            filled.insert(.name)
        }
        if draft.category == .food, draft.kcalPerBaseUnit == nil,
           let kcal = OpenFoodFacts.suggestedKcal(product, unitKind: draft.unitKind)
        {
            draft.kcalPerBaseUnit = kcal
            filled.insert(.calories)
        }
        if draft.category == .water, draft.potableWaterGalPerBaseUnit == nil,
           let gallons = OpenFoodFacts.suggestedWaterGal(product, unitKind: draft.unitKind)
        {
            draft.potableWaterGalPerBaseUnit = gallons
            filled.insert(.water)
        }
        return (draft, filled)
    }
}
