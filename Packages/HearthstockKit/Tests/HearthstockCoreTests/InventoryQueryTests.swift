import Foundation
import Testing
@testable import HearthstockCore

@Suite struct InventoryQueryTests {
    static let profiles = try! ShelfLifeProfileTable.bundledDefaults()

    static func sections(_ query: InventoryQuery, fixture: PantryFixture) -> [InventorySection] {
        Inventory.sections(fixture.statuses(profiles: profiles), locations: fixture.locations, query: query)
    }

    static func title(_ section: InventorySection) -> String {
        switch section.kind {
        case .location(let path): path.map(\.name).joined(separator: " › ")
        case .category(let category): category.rawValue
        case .unplaced: "unplaced"
        }
    }

    // MARK: Grouping and ordering

    @Test(arguments: [
        (InventoryGrouping.location, ["Garage shelf", "Hall closet", "Hall closet › Go-bag"], [6, 9, 1]),
        (.category, ["food", "water"], [11, 5]),
    ])
    func fixtureGroups(grouping: InventoryGrouping, titles: [String], counts: [Int]) throws {
        let fixture = try PantryFixture.load()
        let sections = Self.sections(InventoryQuery(grouping: grouping), fixture: fixture)
        #expect(sections.map(Self.title) == titles)
        #expect(sections.map(\.lots.count) == counts)
        #expect(sections.map(\.isKit) == titles.map { $0.hasSuffix("Go-bag") })
    }

    @Test(arguments: InventoryGrouping.allCases)
    func lotsGoBySeverityThenUsableBy(grouping: InventoryGrouping) throws {
        let fixture = try PantryFixture.load()
        for section in Self.sections(InventoryQuery(grouping: grouping), fixture: fixture) {
            for (a, b) in zip(section.lots, section.lots.dropFirst()) {
                let ra = Inventory.severityOrder.firstIndex(of: a.state!)!
                let rb = Inventory.severityOrder.firstIndex(of: b.state!)!
                #expect(ra <= rb, "\(Self.title(section)): \(a.product!.name) before \(b.product!.name)")
                if ra == rb, let ua = a.evaluation?.usableBy {
                    if let ub = b.evaluation?.usableBy { #expect(ua <= ub) }
                } else if ra == rb {
                    #expect(b.evaluation?.usableBy == nil, "undated lots go last")
                }
            }
        }
    }

    @Test func garageShelfOrderByHand() throws {
        // Expired tomatoes (usable to 2026-03-02), flour (08-01), tap water (08-06); Inspect peanut butter;
        // Good rain barrel (2027-03-20), rice (2028).
        let fixture = try PantryFixture.load()
        let garage = try #require(Self.sections(InventoryQuery(), fixture: fixture).first)
        #expect(garage.lots.map(\.lot) == [12, 6, 4, 7, 16, 1].map(fixture.lot))
    }

    @Test func childLocationsFollowTheirParentAndSiblingsGoByName() {
        let site = SiteID()
        let garage = Location(siteID: site, name: "Garage")
        let shelf2 = Location(siteID: site, name: "Shelf 2", parentID: garage.id)
        let shelf1 = Location(siteID: site, name: "Shelf 1", parentID: garage.id)
        let bin = Location(siteID: site, name: "Bin", parentID: shelf2.id)
        let attic = Location(siteID: site, name: "Attic")
        let loopAID = LocationID(), loopBID = LocationID()
        let loopA = Location(id: loopAID, siteID: site, name: "Loop A", parentID: loopBID)
        let loopB = Location(id: loopBID, siteID: site, name: "Loop B", parentID: loopAID)
        let paths = Inventory.treeOrder([bin, shelf2, garage, shelf1, attic, loopA, loopB])
        #expect(paths.map { $0.map(\.name).joined(separator: " › ") } == [
            "Attic", "Garage", "Garage › Shelf 1", "Garage › Shelf 2", "Garage › Shelf 2 › Bin",
        ])
    }

    @Test func unplacedLotsComeLast() throws {
        let fixture = try PantryFixture.load()
        let lost = Lot(
            productID: fixture.products[0].id, quantity: 1, acquiredDate: date("2026-01-01"), locationID: LocationID())
        let orphan = Lot(
            productID: ProductID(), quantity: 1, acquiredDate: date("2026-01-01"), locationID: fixture.locations[0].id)
        let statuses = LotStatusEvaluator.statuses(
            for: fixture.site, lots: fixture.lots + [lost, orphan], products: fixture.products,
            locations: fixture.locations, kits: fixture.kits, profiles: Self.profiles, on: fixture.today)

        let byLocation = Inventory.sections(statuses, locations: fixture.locations, query: InventoryQuery())
        #expect(byLocation.last?.kind == .unplaced)
        #expect(byLocation.last?.lots.map(\.lot) == [lost])
        #expect(byLocation.first?.lots.first?.lot == orphan, "a lot that can't be evaluated sorts first")

        let byCategory = Inventory.sections(
            statuses, locations: fixture.locations, query: InventoryQuery(grouping: .category))
        #expect(byCategory.last?.kind == .unplaced)
        #expect(byCategory.last?.lots.map(\.lot) == [orphan])
    }

    // MARK: Search and filters

    @Test(arguments: [
        ("beans", [2, 5]),
        ("BEANS", [2, 5]),
        ("  water ", [3, 4, 14, 15, 16]),
        ("top bin", [1]),
        ("no such thing", []),
        ("", Array(1...16)),
    ])
    func searchMatchesNameAndNotes(search: String, lots: [Int]) throws {
        var fixture = try PantryFixture.load()
        let index = fixture.lots.firstIndex(of: fixture.lot(1))!
        fixture.lots[index].notes = "Top bin, behind the paint"
        let found = Self.sections(InventoryQuery(search: search), fixture: fixture).flatMap(\.lots).map(\.lot.id)
        #expect(Set(found) == Set(lots.map { fixture.lot($0).id }))
    }

    @Test func searchIgnoresDiacritics() {
        let site = Site(name: "Home")
        let pantry = Location(siteID: site.id, name: "Pantry")
        let pepper = Product(
            name: "Jalapeño slices", category: .food, role: .supply, unitKind: .count, kcalPerBaseUnit: 50,
            shelfLifeProfileKey: "canned_high_acid")
        let lot = Lot(
            productID: pepper.id, quantity: 2, acquiredDate: date("2026-01-01"), printedDate: date("2027-01-01"),
            locationID: pantry.id, notes: "Crème brûlée shelf")
        let statuses = LotStatusEvaluator.statuses(
            for: site, lots: [lot], products: [pepper], locations: [pantry], kits: [], profiles: Self.profiles,
            on: date("2026-10-06"))
        for search in ["jalapeno", "JALAPEÑO", "creme brulee"] {
            #expect(Inventory.sections(statuses, locations: [pantry], query: InventoryQuery(search: search)).count == 1)
        }
    }

    @Test func expiringSoonIsUseSoonCautionAndInspect() throws {
        var fixture = try PantryFixture.load()
        // Move the oats' printed date into the notice window so the fixture has a Use soon lot.
        let oats = fixture.lots.firstIndex(of: fixture.lot(11))!
        fixture.lots[oats].printedDate = date("2026-10-20")
        let found = Self.sections(InventoryQuery(expiringSoon: true), fixture: fixture).flatMap(\.lots)
        #expect(Set(found.map(\.lot.id)) == Set([2, 7, 11, 14].map { fixture.lot($0).id }))
        #expect(Set(found.compactMap(\.state)) == [.useSoon, .caution, .inspect])
    }

    @Test func categoryFilterAndSearchCombine() throws {
        let fixture = try PantryFixture.load()
        let water = Self.sections(InventoryQuery(category: .water), fixture: fixture).flatMap(\.lots)
        #expect(Set(water.map(\.lot.id)) == Set([3, 4, 14, 15, 16].map { fixture.lot($0).id }))

        let bottled = Self.sections(
            InventoryQuery(grouping: .category, search: "bottled", category: .water), fixture: fixture)
        #expect(bottled.map(Self.title) == ["water"])
        #expect(Set(bottled.flatMap(\.lots).map(\.lot.id)) == Set([3, 14].map { fixture.lot($0).id }))

        let soonWater = Self.sections(InventoryQuery(expiringSoon: true, category: .water), fixture: fixture)
        #expect(soonWater.flatMap(\.lots).map(\.lot) == [fixture.lot(14)])
    }

    @Test func noMatchesIsAnEmptyList() throws {
        let fixture = try PantryFixture.load()
        #expect(Self.sections(InventoryQuery(search: "zzz", category: .food), fixture: fixture).isEmpty)
        #expect(Inventory.sections([], locations: [], query: InventoryQuery()).isEmpty)
        #expect(Self.sections(InventoryQuery(category: .medical), fixture: fixture).isEmpty)
    }
}
