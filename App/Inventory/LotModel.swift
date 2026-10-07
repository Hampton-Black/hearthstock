import Foundation
import HearthstockCore

/// One lot, live: the status `LotStatusEvaluator` gives it in the latest snapshot. Nil once it's used up or deleted.
@MainActor @Observable
final class LotModel: RunwayInputsModel {
    var phase: FeedPhase = .loading
    var inputs: RunwayInputs?
    var today: CalendarDate
    let lotID: LotID
    private(set) var status: LotStatus?
    private let profiles: ShelfLifeProfileTable

    init(lotID: LotID, profiles: ShelfLifeProfileTable, today: CalendarDate) {
        self.lotID = lotID
        self.profiles = profiles
        self.today = today
    }

    func recompute() {
        guard let inputs else { return }
        status = LotStatusEvaluator.statuses(for: inputs, profiles: profiles, on: today).first { $0.id == lotID }
    }
}
