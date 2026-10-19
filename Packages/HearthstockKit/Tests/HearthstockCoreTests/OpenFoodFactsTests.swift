import Foundation
import Testing
@testable import HearthstockCore

@Suite struct OpenFoodFactsTests {
    static let profiles = try! ShelfLifeProfileTable.bundledDefaults()
    static let categories = try! OFFCategoryMap.bundled()

    static func fixture(_ name: String) throws -> Data {
        guard let url = Bundle.module.url(
            forResource: name, withExtension: "json", subdirectory: "Fixtures/openfoodfacts")
        else { throw CocoaError(.fileNoSuchFile) }
        return try Data(contentsOf: url)
    }

    static func lookedUp(_ name: String, status: Int = 200) throws -> LookedUpProduct {
        guard case .found(let product) = OpenFoodFacts.decode(try fixture(name), httpStatus: status) else {
            throw CocoaError(.coderValueNotFound)
        }
        return product
    }

    static func draft(_ name: String) throws -> ProductDraft {
        OpenFoodFacts.draft(from: try lookedUp(name), barcode: nil, categories: categories, profiles: profiles)
    }

    struct Expected: Sendable, CustomTestStringConvertible {
        var fixture: String
        var name: String
        var isWater = false
        var unitKind: UnitKind = .count
        var kcal: Double?
        var water: Double?
        var profile: ShelfLifeProfileKey = "unknown_food"
        var testDescription: String { fixture }
    }

    static let expectations: [Expected] = [
        // Hampton's pantry, as recorded: no net quantity, so no calories per item, and few category tags.
        Expected(fixture: "corn", name: "H-E-B Whole Kernel Corn"),
        Expected(fixture: "cinnamon-rolls", name: "Walmart Cinnamon rolls"),
        Expected(fixture: "protein-bar", name: "Cookies & Cream Pure Protein"),  // the name already holds the brand
        Expected(fixture: "rice-25lb", name: "Kings Enriched Long Grain Parboiled Rice"),
        Expected(fixture: "water-40pack", name: ""),  // nothing to go on: the form asks for the name and category
        // With a net quantity.
        Expected(fixture: "campbells-soup", name: "Campbell's Cream Of Mushroom Soup, 10.5 oz",
                 kcal: 248, profile: "canned_low_acid"),  // 83.33 kcal/100 g × 297.67 g, rounded
        Expected(fixture: "barilla-penne", name: "Barilla Penne, 1 lb",  // 1 lb is a single box: count
                 kcal: 1620, profile: "pasta_dry"),  // 357.14 × 4.5359, rounded
        Expected(fixture: "derived-rice-25lb-with-size", name: "Kings Enriched Long Grain Parboiled Rice, 25 lb",
                 unitKind: .mass, kcal: 1641, profile: "white_rice"),  // per lb, rounded
        Expected(fixture: "derived-soup-kj-only", name: "Campbell's Cream Of Mushroom Soup, 10.5 oz",
                 kcal: 248, profile: "canned_low_acid"),
        Expected(fixture: "derived-water-named",
                 name: "Kirkland Signature Purified Drinking Water, 40 x 16.9 fl oz", isWater: true,
                 water: 0.132, profile: "bottled_water"),  // 500 ml, to a thousandth of a gallon
    ]

    @Test(arguments: expectations)
    func fixtureMapsToTheExpectedDraft(expected: Expected) throws {
        let draft = try Self.draft(expected.fixture)
        #expect(draft.name == expected.name)
        #expect(draft.category == (expected.isWater ? .water : .food))
        #expect(draft.unitKind == expected.unitKind)
        #expect(draft.shelfLifeProfileKey == expected.profile)
        switch (draft.kcalPerBaseUnit, expected.kcal) {
        case let (actual?, wanted?): #expect(isApproximately(actual, wanted, tolerance: 1e-6))
        case (nil, nil): break
        default: Issue.record("kcal \(String(describing: draft.kcalPerBaseUnit)), expected \(String(describing: expected.kcal))")
        }
        switch (draft.potableWaterGalPerBaseUnit, expected.water) {
        case let (actual?, wanted?): #expect(isApproximately(actual, wanted, tolerance: 1e-9))
        case (nil, nil): break
        default: Issue.record("water \(String(describing: draft.potableWaterGalPerBaseUnit))")
        }
    }

    @Test func draftCarriesTheBarcode() throws {
        let code = try Barcode("051000012616")
        let draft = OpenFoodFacts.draft(
            from: try Self.lookedUp("campbells-soup"), barcode: code, categories: Self.categories, profiles: Self.profiles)
        #expect(draft.barcode == "0051000012616")
        #expect(try draft.product().barcode == "0051000012616")
    }

    @Test func numericStringsDecode() throws {
        let rice = try Self.lookedUp("derived-rice-25lb-with-size")
        #expect(rice.netQuantity.map { isApproximately($0, 11339.809) } == true)
        #expect(rice.netQuantityUnit == .gram)
    }

    @Test func kilojoulesOnlyConvertsToKilocalories() throws {
        let soup = try Self.lookedUp("derived-soup-kj-only")
        #expect(soup.kcalPer100.map { isApproximately($0, 348.67 / 4.184) } == true)
    }

    @Test func perServingCaloriesAreKeptButNeverUsedForAnItem() throws {
        let bar = try Self.lookedUp("protein-bar")
        #expect(bar.kcalPerServing == 190)
        #expect(OpenFoodFacts.kcalPerBaseUnit(bar, unitKind: .count) == nil)
    }

    /// Switching a found product to mass or volume can still give calories, since those need only the per-100 value.
    @Test func caloriesPerPoundNeedNoNetQuantity() throws {
        let rice = try Self.lookedUp("rice-25lb")
        let perPound = try #require(OpenFoodFacts.kcalPerBaseUnit(rice, unitKind: .mass))
        #expect(isApproximately(perPound, 361.702127659574 * 4.5359237, tolerance: 1e-6))
    }

    // MARK: Responses

    @Test func notFoundResponses() throws {
        #expect(OpenFoodFacts.decode(try Self.fixture("not-found-rhino-pak-jug"), httpStatus: 404) == .notFound)
        // The same envelope with a 200 still says not found.
        #expect(OpenFoodFacts.decode(try Self.fixture("not-found-rhino-pak-jug"), httpStatus: 200) == .notFound)
    }

    @Test(arguments: [
        (302, LookupResult.notFound),  // redirected to a sister database (beauty, pet food): not pantry stock
        (404, .notFound),
        (429, .unavailable(.rateLimited)),
        (500, .unavailable(.serverError)),
        (503, .unavailable(.serverError)),
        (400, .unavailable(.serverError)),
    ])
    func statusCodes(status: Int, expected: LookupResult) {
        #expect(OpenFoodFacts.decode(Data("{}".utf8), httpStatus: status) == expected)
    }

    @Test(arguments: ["", "<html>Bad gateway</html>", "[1, 2]"])
    func unreadableBodyIsAServerError(body: String) {
        #expect(OpenFoodFacts.decode(Data(body.utf8), httpStatus: 200) == .unavailable(.serverError))
    }

    @Test func malformedFieldsAreLeftEmpty() {
        let body = #"{"status": "success", "result": {"id": "product_found"}, "product": {"product_name": 42, "brands": "", "product_quantity": "lots", "product_quantity_unit": "g", "nutriments": {"energy-kcal_100g": "n/a"}, "categories_tags": "en:rices"}}"#
        #expect(OpenFoodFacts.decode(Data(body.utf8), httpStatus: 200) == .found(LookedUpProduct()))
    }

    @Test func lookedUpProductRoundTripsThroughJSON() throws {
        for name in ["campbells-soup", "derived-water-named", "water-40pack"] {
            let product = try Self.lookedUp(name)
            #expect(try JSONDecoder().decode(LookedUpProduct.self, from: JSONEncoder().encode(product)) == product)
        }
    }

    // MARK: Unit kind (Decision 12)

    @Test(arguments: [
        (907.0, LookedUpProduct.NetUnit.gram, UnitKind.count),
        (908.0, .gram, .mass),
        (3785.0, .millilitre, .count),
        (3786.0, .millilitre, .volume),
    ])
    func unitKindThresholds(net: Double, unit: LookedUpProduct.NetUnit, kind: UnitKind) {
        #expect(OpenFoodFacts.unitKind(LookedUpProduct(netQuantity: net, netQuantityUnit: unit)) == kind)
    }

    @Test func unknownNetQuantityIsCount() {
        #expect(OpenFoodFacts.unitKind(LookedUpProduct()) == .count)
    }

    // MARK: Categories

    @Test func severalMatchingTagsTakeTheShortestWindow() {
        // White rice (24-month extension) and brown rice (3): brown wins.
        #expect(Self.categories.profile(for: ["en:rices", "en:brown-rices"], in: Self.profiles) == "brown_rice")
        // Canned foods (low acid, 24) and canned fruit (high acid, 12): high acid wins.
        #expect(Self.categories.profile(for: ["en:canned-foods", "en:canned-fruits"], in: Self.profiles)
            == "canned_high_acid")
        // Honey never expires, so anything dated beats it.
        #expect(Self.categories.profile(for: ["en:honeys", "en:canned-foods"], in: Self.profiles) == "canned_low_acid")
    }

    @Test func unknownTagsMatchNothing() {
        #expect(Self.categories.profile(for: ["en:snacks", "en:cakes"], in: Self.profiles) == nil)
    }

    @Test func everyMappedProfileExists() {
        for (tag, key) in Self.categories.profiles {
            #expect(Self.profiles[key] != nil, "\(tag) → \(key)")
        }
    }

    // MARK: Filling a draft (spec: never overwrite what the user entered)

    @Test func fillingLeavesEveryUserSetFieldAlone() throws {
        let soup = try Self.lookedUp("campbells-soup")
        let typed = ProductDraft(
            name: "Mushroom soup", barcode: "0051000012616", category: .food, unitKind: .count, kcalPerBaseUnit: 250,
            shelfLifeProfileKey: "canned_high_acid")
        let (draft, filled) = typed.fillingEmptyFields(from: soup)
        #expect(draft == typed)
        #expect(filled.isEmpty)
    }

    @Test func fillingFillsOnlyEmptyFields() throws {
        let soup = try Self.lookedUp("campbells-soup")
        let typed = ProductDraft(name: " ", category: .food, unitKind: .count, shelfLifeProfileKey: "unknown_food")
        let (draft, filled) = typed.fillingEmptyFields(from: soup)
        #expect(filled == [.name, .calories])
        #expect(draft.name == "Campbell's Cream Of Mushroom Soup, 10.5 oz")
        #expect(draft.kcalPerBaseUnit == 248)
        #expect(draft.shelfLifeProfileKey == "unknown_food")  // profile, category and unit kind stay as entered
        #expect(draft.unitKind == .count)
    }

    @Test func fillingUsesTheDraftsOwnUnitKind() throws {
        let rice = try Self.lookedUp("rice-25lb")
        let typed = ProductDraft(name: "Rice", category: .food, unitKind: .mass)
        let (draft, filled) = typed.fillingEmptyFields(from: rice)
        #expect(filled == [.calories])
        #expect(draft.kcalPerBaseUnit == 1641)
    }

    @Test func fillingWaterGallons() throws {
        let water = try Self.lookedUp("derived-water-named")
        let typed = ProductDraft(name: "Water", category: .water, unitKind: .count)
        let (draft, filled) = typed.fillingEmptyFields(from: water)
        #expect(filled == [.water])
        #expect(draft.potableWaterGalPerBaseUnit.map { isApproximately($0, 0.132) } == true)
    }

    @Test func notFoundGivesNoDraft() throws {
        guard case .notFound = OpenFoodFacts.decode(try Self.fixture("not-found-rhino-pak-jug"), httpStatus: 404) else {
            Issue.record("expected not found")
            return
        }
    }
}
