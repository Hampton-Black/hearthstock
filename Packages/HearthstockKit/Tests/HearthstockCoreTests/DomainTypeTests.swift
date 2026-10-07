import Foundation
import Testing
@testable import HearthstockCore

@Suite struct DomainTypeTests {
    @Test func personDefaults() {
        let person = Person(siteID: SiteID(), name: "Alex")
        #expect(isApproximately(person.kcalPerDay, 2000))
        #expect(isApproximately(person.waterGalPerDay, 1.0))
    }

    @Test func kitIsExcludedFromSiteRunwayByDefault() {
        let kit = Kit(locationID: LocationID())
        #expect(kit.countsTowardSiteRunway == false)
        #expect(kit.templateID == nil)
    }

    @Test func productBaseUnitFollowsUnitKind() {
        let rice = Product(name: "White rice", category: .food, role: .supply, unitKind: .mass,
                           kcalPerBaseUnit: 1650, shelfLifeProfileKey: "white_rice")
        #expect(rice.baseUnit == .pound)
        #expect(rice.barcode == nil)
        #expect(rice.potableWaterGalPerBaseUnit == nil)
    }

    @Test func lotDefaultsAreUnopenedAndActive() {
        let lot = Lot(productID: ProductID(), quantity: 20, acquiredDate: day(2026, 1, 5),
                      locationID: LocationID())
        #expect(lot.opened == false)
        #expect(lot.archived == false)
        #expect(lot.packaging == .none)
        #expect(lot.printedDate == nil)
        #expect(lot.climateOverride == nil)
    }

    @Test(arguments: [
        (ClimateClass.coolDry, 1.25 as Double?),
        (.rootCellar, 1.25),
        (.climateControlled, 1.0),
        (.insulatedUnconditioned, 0.75),
        (.hot, 0.5),
        (.vehicle, 0.33),
        (.refrigerated, nil),
        (.frozen, nil),
    ])
    func climateMultipliersMatchSpec(climate: ClimateClass, expected: Double?) {
        switch (climate.defaultWindowMultiplier, expected) {
        case (nil, nil): break
        case let (actual?, expected?): #expect(isApproximately(actual, expected))
        default: Issue.record("\(climate): got \(String(describing: climate.defaultWindowMultiplier)), expected \(String(describing: expected))")
        }
    }

    @Test func domainTypesRoundTripThroughJSON() throws {
        let location = Location(siteID: SiteID(), name: "Garage shelf", climateClass: .hot, humidity: .humid)
        let lot = Lot(productID: ProductID(), quantity: 5, acquiredDate: day(2025, 3, 1),
                      printedDate: day(2027, 3, 1), packaging: .mylarO2,
                      locationID: location.id, climateOverride: .coolDry, notes: "Top bin")
        #expect(try JSONDecoder().decode(Location.self, from: JSONEncoder().encode(location)) == location)
        #expect(try JSONDecoder().decode(Lot.self, from: JSONEncoder().encode(lot)) == lot)
    }
}

@Suite struct ClimateResolutionTests {
    let site = SiteID()

    private func index(_ locations: [Location]) -> [LocationID: Location] {
        Dictionary(uniqueKeysWithValues: locations.map { ($0.id, $0) })
    }

    private func lot(at location: LocationID, override: ClimateClass? = nil) -> Lot {
        Lot(productID: ProductID(), quantity: 1, acquiredDate: day(2026, 1, 1),
            locationID: location, climateOverride: override)
    }

    @Test func inheritsThroughThreeLevelChain() throws {
        let garage = Location(siteID: site, name: "Garage", climateClass: .hot)
        let shelf = Location(siteID: site, name: "Shelf", parentID: garage.id)
        let bin = Location(siteID: site, name: "Bin", parentID: shelf.id)
        let locations = index([garage, shelf, bin])
        #expect(try resolvedClimate(for: lot(at: bin.id), locations: locations) == .hot)
    }

    @Test func nearestAncestorWins() throws {
        let house = Location(siteID: site, name: "House", climateClass: .climateControlled)
        let basement = Location(siteID: site, name: "Basement", parentID: house.id, climateClass: .coolDry)
        let shelf = Location(siteID: site, name: "Shelf", parentID: basement.id)
        let locations = index([house, basement, shelf])
        #expect(try resolvedClimate(for: lot(at: shelf.id), locations: locations) == .coolDry)
    }

    @Test func lotOverrideWins() throws {
        let garage = Location(siteID: site, name: "Garage", climateClass: .hot)
        let fridge = Location(siteID: site, name: "Garage fridge spot", parentID: garage.id)
        let locations = index([garage, fridge])
        let resolved = try resolvedClimate(for: lot(at: fridge.id, override: .refrigerated), locations: locations)
        #expect(resolved == .refrigerated)
    }

    @Test func defaultsToClimateControlledWhenNothingIsSet() throws {
        let room = Location(siteID: site, name: "Room")
        let closet = Location(siteID: site, name: "Closet", parentID: room.id)
        let locations = index([room, closet])
        #expect(try resolvedClimate(for: lot(at: closet.id), locations: locations) == .climateControlled)
    }

    @Test func cycleIsAnError() {
        var a = Location(siteID: site, name: "A")
        var b = Location(siteID: site, name: "B")
        let c = Location(siteID: site, name: "C", parentID: b.id)
        a.parentID = c.id
        b.parentID = a.id
        let locations = index([a, b, c])
        #expect(throws: ClimateResolutionError.cycle(at: c.id)) {
            try resolvedClimate(of: c.id, locations: locations)
        }
    }

    @Test func selfParentIsACycle() {
        var a = Location(siteID: site, name: "A")
        a.parentID = a.id
        #expect(throws: ClimateResolutionError.cycle(at: a.id)) {
            try resolvedClimate(of: a.id, locations: index([a]))
        }
    }

    @Test func cycleAboveAClassedLocationIsNotReached() throws {
        // Resolution stops at the first location with a class, so a cycle further up is never walked.
        var a = Location(siteID: site, name: "A")
        a.parentID = a.id
        let b = Location(siteID: site, name: "B", parentID: a.id, climateClass: .vehicle)
        #expect(try resolvedClimate(of: b.id, locations: index([a, b])) == .vehicle)
    }

    @Test func missingLocationIsAnError() {
        let ghost = LocationID()
        let child = Location(siteID: site, name: "Child", parentID: ghost)
        #expect(throws: ClimateResolutionError.missingLocation(ghost)) {
            try resolvedClimate(of: child.id, locations: index([child]))
        }
    }
}

private func day(_ year: Int, _ month: Int, _ day: Int) -> CalendarDate {
    CalendarDate(year: year, month: month, day: day)!
}

@Suite struct StorageClimateTests {
    let site = SiteID()

    private func lot(override: ClimateClass? = nil) -> Lot {
        Lot(productID: ProductID(), quantity: 1, acquiredDate: day(2026, 1, 1),
            locationID: LocationID(), climateOverride: override)
    }

    @Test func nothingSetFallsBackToTheFallbackClass() {
        let shelf = Location(siteID: site, name: "Shelf")
        let climate = StorageClimate(lot: lot(), chain: [shelf])
        #expect(climate == StorageClimate(climateClass: .fallback, windowMultiplier: nil))
    }

    @Test func classAloneUsesItsDefaultMultiplier() {
        let garage = Location(siteID: site, name: "Garage", climateClass: .hot)
        #expect(StorageClimate(lot: lot(), chain: [garage]) == StorageClimate(climateClass: .hot, windowMultiplier: nil))
    }

    @Test func locationOverrideAloneKeepsTheClass() {
        let garage = Location(siteID: site, name: "Garage", climateClass: .hot, climateMultiplierOverride: 0.6)
        #expect(StorageClimate(lot: lot(), chain: [garage]) == StorageClimate(climateClass: .hot, windowMultiplier: 0.6))
    }

    @Test func childInheritsClassAndOverrideFromParent() {
        let garage = Location(siteID: site, name: "Garage", climateClass: .hot, climateMultiplierOverride: 0.6)
        let shelf = Location(siteID: site, name: "Shelf", parentID: garage.id)
        #expect(StorageClimate(lot: lot(), chain: [shelf, garage]) == StorageClimate(climateClass: .hot, windowMultiplier: 0.6))
    }

    @Test func childOverrideAloneWinsOverParentOverrideAndInheritsParentClass() {
        let garage = Location(siteID: site, name: "Garage", climateClass: .hot, climateMultiplierOverride: 0.6)
        let shelf = Location(siteID: site, name: "Shelf", parentID: garage.id, climateMultiplierOverride: 0.8)
        #expect(StorageClimate(lot: lot(), chain: [shelf, garage]) == StorageClimate(climateClass: .hot, windowMultiplier: 0.8))
    }

    @Test func childsOwnClassShadowsParentsOverride() {
        let garage = Location(siteID: site, name: "Garage", climateClass: .hot, climateMultiplierOverride: 0.6)
        let cellar = Location(siteID: site, name: "Cellar", parentID: garage.id, climateClass: .coolDry)
        #expect(StorageClimate(lot: lot(), chain: [cellar, garage]) == StorageClimate(climateClass: .coolDry, windowMultiplier: nil))
    }

    @Test func overrideOnAnAncestorAboveTheNearestClassIsShadowed() {
        let house = Location(siteID: site, name: "House", climateMultiplierOverride: 0.9)
        let garage = Location(siteID: site, name: "Garage", parentID: house.id, climateClass: .hot)
        #expect(StorageClimate(lot: lot(), chain: [garage, house]) == StorageClimate(climateClass: .hot, windowMultiplier: nil))
    }

    @Test func overrideWithoutAnyClassInTheChainUsesFallbackClass() {
        let shelf = Location(siteID: site, name: "Shelf", climateMultiplierOverride: 0.7)
        #expect(StorageClimate(lot: lot(), chain: [shelf]) == StorageClimate(climateClass: .fallback, windowMultiplier: 0.7))
    }

    @Test func lotClimateOverrideReplacesTheWholeChain() {
        let garage = Location(siteID: site, name: "Garage", climateClass: .hot, climateMultiplierOverride: 0.6)
        let climate = StorageClimate(lot: lot(override: .coolDry), chain: [garage])
        #expect(climate == StorageClimate(climateClass: .coolDry, windowMultiplier: nil))
    }

    @Test func locationRoundTripsItsMultiplierOverrideThroughJSON() throws {
        let location = Location(siteID: site, name: "Shed", climateClass: .hot, climateMultiplierOverride: 0.6)
        let decoded = try JSONDecoder().decode(Location.self, from: JSONEncoder().encode(location))
        #expect(decoded == location)
        #expect(decoded.climateMultiplierOverride == 0.6)
    }

    @Test func locationJSONWithoutTheFieldStillDecodes() throws {
        let location = Location(siteID: site, name: "Shed")
        var object = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(location)) as? [String: Any])
        object.removeValue(forKey: "climateMultiplierOverride")
        let decoded = try JSONDecoder().decode(Location.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(decoded.climateMultiplierOverride == nil)
    }
}
