import Foundation
import Testing
@testable import HearthstockCore

@Suite struct PantryWalkTests {
    static let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
    let shelf = LocationID()
    let rice = ProductID(), beans = ProductID(), jug = ProductID()
    let riceLot = LotID(), beansLot = LotID(), jugLot = LotID()

    /// A create, a product + lot create, an add-to-lot and a no-date product.
    func walk() -> PantryWalk {
        var walk = PantryWalk(locationID: shelf, startedAt: Self.start)
        walk.record(.createdLot(riceLot, product: rice, amount: 20, date: .printed))
        walk.record(.createdProductAndLot(beansLot, product: beans, amount: 6, date: .missing))
        walk.record(.added(beansLot, product: beans, amount: 1))
        walk.record(.createdLot(jugLot, product: jug, amount: 1, date: .notNeeded))
        return walk
    }

    @Test func countsItemsAndLots() {
        let walk = walk()
        #expect(walk.itemCount == 4)
        #expect(walk.lotCount == 3)
    }

    @Test func groupsByProductInFirstAddedOrder() {
        #expect(walk().groups == [
            PantryWalk.Group(productID: rice, times: 1, lots: [riceLot]),
            PantryWalk.Group(productID: beans, times: 2, lots: [beansLot]),
            PantryWalk.Group(productID: jug, times: 1, lots: [jugLot]),
        ])
    }

    @Test func undoPlansReverseEachKindOfWrite() {
        var walk = walk()
        #expect(walk.undoLast() == .deleteLot(jugLot))
        #expect(walk.undoLast() == .consume(beansLot, amount: 1))
        #expect(walk.undoLast() == .deleteLotAndProduct(beansLot, beans))
        #expect(walk.undoLast() == .deleteLot(riceLot))
        #expect(walk.undoLast() == nil)
        #expect(walk.itemCount == 0)
    }

    @Test func lotsNeedingADateAreTheSkippedOnes() {
        var walk = walk()
        walk.record(.createdLot(LotID(), product: rice, amount: 5, date: .noPrintedDate))
        #expect(walk.lotsNeedingADate == [beansLot])
    }

    @Test func undoingAnAddTakesItOffTheNeedsADateList() {
        var walk = walk()
        _ = walk.undoLast()  // jug
        _ = walk.undoLast()  // the add
        _ = walk.undoLast()  // the beans product + lot
        #expect(walk.lotsNeedingADate.isEmpty)
        #expect(walk.groups.map(\.productID) == [rice])
    }

    @Test func latestLotForAddAnother() {
        let walk = walk()
        #expect(walk.latestLot(of: beans) == beansLot)
        #expect(walk.latestLot(of: ProductID()) == nil)
    }

    @Test func elapsedTimeFromTheInjectedClock() {
        let walk = walk()
        #expect(walk.elapsed(at: Self.start.addingTimeInterval(372)) == 372)
        #expect(walk.elapsed(at: Self.start.addingTimeInterval(-5)) == 0)
    }
}
