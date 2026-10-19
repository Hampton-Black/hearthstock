import Foundation
import Testing
@testable import HearthstockCore

@Suite struct ScanResolutionTests {
    static let profiles = try! ShelfLifeProfileTable.bundledDefaults()
    static let beansCode = try! Barcode("036000291452")
    static let unknownCode = try! Barcode("4006381333931")

    struct World {
        let home = Site(name: "Home")
        let cabin = Site(name: "Cabin")
        let pantry: Location
        let shed: Location
        let beans = Product(
            name: "Black beans", barcode: ScanResolutionTests.beansCode.rawValue, category: .food, role: .supply,
            unitKind: .count, kcalPerBaseUnit: 385, shelfLifeProfileKey: "canned_low_acid")
        var lots: [Lot] = []

        init() {
            pantry = Location(siteID: home.id, name: "Pantry", climateClass: .climateControlled)
            shed = Location(siteID: cabin.id, name: "Shed", climateClass: .hot)
        }

        @discardableResult
        mutating func addBeans(at location: Location, acquired: String, archived: Bool = false) -> Lot {
            let lot = Lot(productID: beans.id, quantity: 6, acquiredDate: date(acquired), printedDate: date("2028-01-01"),
                          locationID: location.id, archived: archived)
            lots.append(lot)
            return lot
        }

        func statuses(site: Site) -> [LotStatus] {
            LotStatusEvaluator.statuses(
                for: site, lots: lots, products: [beans], locations: [pantry, shed], kits: [], profiles: profiles,
                on: date("2026-10-06"))
        }
    }

    @Test func knownProductWithLotsHereListsThemNewestFirst() throws {
        var world = World()
        let older = world.addBeans(at: world.pantry, acquired: "2026-01-01")
        let newer = world.addBeans(at: world.pantry, acquired: "2026-09-01")
        world.addBeans(at: world.shed, acquired: "2026-10-01")
        let outcome = ScanResolution.resolve(
            Self.beansCode, products: [world.beans], statuses: world.statuses(site: world.home), lookup: nil)
        guard case let .known(product, lots) = outcome else {
            Issue.record("expected known, got \(outcome)")
            return
        }
        #expect(product == world.beans)
        #expect(lots.map(\.id) == [newer.id, older.id])
    }

    @Test func knownProductWithLotsOnlyAtAnotherSiteHasNoLots() {
        var world = World()
        world.addBeans(at: world.shed, acquired: "2026-10-01")
        let outcome = ScanResolution.resolve(
            Self.beansCode, products: [world.beans], statuses: world.statuses(site: world.home), lookup: nil)
        #expect(outcome == .known(world.beans, lots: []))
    }

    @Test func knownProductIgnoresTheLookup() {
        let world = World()
        let outcome = ScanResolution.resolve(
            Self.beansCode, products: [world.beans], statuses: [], lookup: .found(ProductDraft(name: "Other")))
        #expect(outcome == .known(world.beans, lots: []))
    }

    @Test func aUPCAScanFindsTheProductSavedFromItsEAN13() throws {
        let world = World()
        let outcome = ScanResolution.resolve(
            try Barcode("0036000291452"), products: [world.beans], statuses: [], lookup: nil)
        #expect(outcome == .known(world.beans, lots: []))
    }

    @Test func unknownWithNoLookupYetIsLookingUp() {
        #expect(ScanResolution.resolve(Self.unknownCode, products: [], statuses: [], lookup: nil)
            == .lookingUp(Self.unknownCode))
    }

    @Test func foundTakesTheDraftWithTheBarcode() {
        let draft = ProductDraft(name: "Bush's Black Beans, 15 oz", unitKind: .count, kcalPerBaseUnit: 385)
        let outcome = ScanResolution.resolve(Self.unknownCode, products: [], statuses: [], lookup: .found(draft))
        var expected = draft
        expected.barcode = Self.unknownCode.rawValue
        #expect(outcome == .found(expected))
    }

    @Test func notFoundKeepsOnlyTheBarcode() {
        let outcome = ScanResolution.resolve(Self.unknownCode, products: [], statuses: [], lookup: .notFound)
        #expect(outcome == .notFound(ProductDraft(barcode: Self.unknownCode.rawValue, unitKind: .count)))
    }

    @Test(arguments: LookupUnavailableReason.allCases)
    func unavailableSaysWhy(reason: LookupUnavailableReason) {
        let outcome = ScanResolution.resolve(
            Self.unknownCode, products: [], statuses: [], lookup: .unavailable(reason))
        #expect(outcome == .lookupUnavailable(
            ProductDraft(barcode: Self.unknownCode.rawValue, unitKind: .count), reason: reason))
    }
}

@Suite struct ScanDebouncerTests {
    static let a = try! Barcode("036000291452")
    static let b = try! Barcode("4006381333931")
    static let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    /// Feeds `steps` (seconds from the start, codes in frame) and returns each step's event.
    static func run(_ steps: [(Double, Set<Barcode>)], debouncer: inout ScanDebouncer) -> [ScanDebouncer.Event?] {
        steps.map { debouncer.sighted($0.1, at: start.addingTimeInterval($0.0)) }
    }

    @Test func continuousSightingsAreOneScan() {
        var debouncer = ScanDebouncer()
        let events = Self.run([(0, [Self.a]), (0.1, [Self.a]), (0.5, [Self.a]), (3, [Self.a])], debouncer: &debouncer)
        #expect(events == [.scan(Self.a), nil, nil, nil])
        debouncer.resume()
        #expect(debouncer.sighted([Self.a], at: Self.start.addingTimeInterval(10)) == nil)
    }

    @Test func outOfFrameForOneSecondIsTheSameScan() {
        var debouncer = ScanDebouncer()
        let first = Self.run([(0, [Self.a])], debouncer: &debouncer)
        debouncer.resume()
        let rest = Self.run([(0.5, []), (1.5, [Self.a])], debouncer: &debouncer)
        #expect(first + rest == [.scan(Self.a), nil, nil])
    }

    @Test func outOfFrameForTwoSecondsIsANewScan() {
        var debouncer = ScanDebouncer()
        let first = Self.run([(0, [Self.a])], debouncer: &debouncer)
        debouncer.resume()
        let rest = Self.run([(0.5, []), (2.5, [Self.a])], debouncer: &debouncer)
        #expect(first + rest == [.scan(Self.a), nil, .scan(Self.a)])
    }

    @Test func seenAgainAfterBeingAddedIsARepeat() {
        var debouncer = ScanDebouncer()
        _ = Self.run([(0, [Self.a])], debouncer: &debouncer)
        debouncer.added(Self.a)
        debouncer.resume()
        let rest = Self.run([(1, []), (4, [Self.a])], debouncer: &debouncer)
        #expect(rest == [nil, .repeat(Self.a)])
    }

    @Test func aSecondCodeWhileHoldingIsIgnored() {
        var debouncer = ScanDebouncer()
        let events = Self.run([(0, [Self.a]), (1, [Self.a, Self.b]), (2, [Self.b])], debouncer: &debouncer)
        #expect(events == [.scan(Self.a), nil, nil])
        #expect(debouncer.isHolding)
    }

    @Test func aCodeStillInFrameAfterResumeIsTheNextScan() {
        var debouncer = ScanDebouncer()
        _ = Self.run([(0, [Self.a]), (1, [Self.a, Self.b])], debouncer: &debouncer)
        debouncer.added(Self.a)
        debouncer.resume()
        // The can just added is still in frame and stays quiet; the next one fires.
        #expect(debouncer.sighted([Self.a, Self.b], at: Self.start.addingTimeInterval(2)) == .scan(Self.b))
    }

    @Test func aCodeThatLeftWhileHoldingIsForgotten() {
        var debouncer = ScanDebouncer()
        _ = Self.run([(0, [Self.a]), (1, [Self.a, Self.b]), (1.2, [Self.a])], debouncer: &debouncer)
        debouncer.resume()
        #expect(debouncer.sighted([Self.a], at: Self.start.addingTimeInterval(2)) == nil)
    }

    @Test func twoCodesAtOnceGiveOneScanThenTheOther() {
        var debouncer = ScanDebouncer()
        #expect(debouncer.sighted([Self.b, Self.a], at: Self.start) == .scan(Self.a))
        debouncer.resume()
        #expect(debouncer.sighted([Self.b, Self.a], at: Self.start.addingTimeInterval(0.5)) == .scan(Self.b))
    }

    @Test func aTypedCodeTakesTheSamePath() {
        var debouncer = ScanDebouncer()
        #expect(debouncer.typed(Self.a) == .scan(Self.a))
        #expect(debouncer.typed(Self.b) == nil)  // holding
        debouncer.added(Self.a)
        debouncer.resume()
        #expect(debouncer.typed(Self.a) == .repeat(Self.a))
        debouncer.resume()
        #expect(debouncer.sighted([Self.b], at: Self.start) == .scan(Self.b))
    }
}
