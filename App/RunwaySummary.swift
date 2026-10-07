import Foundation
import HearthstockCore

/// What the smoke-test screen prints about one site, derived from a runway-inputs snapshot.
struct RunwaySummary: Equatable {
    var siteName: String
    var lotCount: Int
    var runwayText: String
    /// Nothing at the site yet: no lots, locations or people.
    var isEmpty: Bool

    init(inputs: RunwayInputs, profiles: ShelfLifeProfileTable, today: CalendarDate) {
        let runway = RunwayCalculator.runway(for: inputs, profiles: profiles, on: today)
        siteName = inputs.site.name
        lotCount = inputs.lots.count
        isEmpty = inputs.lots.isEmpty && inputs.locations.isEmpty && inputs.occupants.isEmpty
        if let range = runway.effective {
            let limit = runway.limitingCategory.map { ", limited by \($0.rawValue)" } ?? ""
            runwayText = "\(Self.days(range.low)) to \(Self.days(range.high)) days\(limit)"
        } else if runway.problems.contains(.noOccupants) {
            runwayText = "not computed (no occupants)"
        } else {
            runwayText = "not computed"
        }
    }

    private static func days(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }
}

extension CalendarDate {
    /// Today on the device's calendar.
    static func today(calendar: Calendar = .current, now: Date = Date()) -> CalendarDate {
        let parts = calendar.dateComponents([.year, .month, .day], from: now)
        return CalendarDate(year: parts.year ?? 1970, month: parts.month ?? 1, day: parts.day ?? 1)
            ?? CalendarDate(year: 1970, month: 1, day: 1)!
    }
}
