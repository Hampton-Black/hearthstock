import Foundation
import HearthstockCore

/// Sentences about one lot, built from its Core status. Nothing here decides a state; it only words one.
enum LotText {
    /// Why the lot is in its state.
    static func why(_ status: LotStatus, today: CalendarDate) -> String {
        guard let evaluation = status.evaluation, let profile = status.profile else {
            return problem(status)
        }
        let label = profile.dateType.label
        guard let timeline = evaluation.timeline, let usableBy = evaluation.usableBy else {
            if evaluation.flags.contains(.missingDate) {
                return "No printed date, so it counts as Good. Add the date from the package if it has one."
            }
            return "\(profile.name) doesn't expire, so it stays Good."
        }
        switch evaluation.state {
        case .good:
            if timeline.fromPrintedDate, let printed = status.lot.printedDate {
                return "In date: \(label.lowercased()) \(printed.medium)."
            }
            return "Good until \(timeline.inspectFrom.monthYear), then check it before use. Usable until \(usableBy.monthYear)."
        case .useSoon:
            let printed = status.lot.printedDate ?? timeline.goodThrough
            let days = today.days(until: printed)
            let when = days == 0 ? "today" : days == 1 ? "tomorrow" : "in \(days) days"
            return "\(label) \(printed.medium), \(when). Use it soon; it still counts fully toward runway."
        case .caution:
            return "Past its best-by date but still usable until \(usableBy.monthYear). Eat these first and rotate in fresh stock."
        case .inspect:
            return "In the last 20% of its window, usable until \(usableBy.monthYear). Check before use; bulging, rusted or leaking cans go regardless of date."
        case .expired:
            return "Past its usable-by date (\(usableBy.medium)). It no longer counts toward runway."
        }
    }

    static func problem(_ status: LotStatus) -> String {
        switch status.problem {
        case .unresolvedLocation?: "Its location is missing, so it can't be evaluated."
        case .missingProduct?: "Its product is missing, so it can't be evaluated."
        case .missingProfile(_, let key)?: "Its shelf-life profile (\(key)) isn't in the table, so it can't be evaluated."
        default: "It can't be evaluated."
        }
    }

    /// What the lot adds to runway: "+2,310 kcal, high end only".
    static func runway(_ effect: RunwayEffect) -> String {
        switch effect {
        case .counts(_, let amount, let unit, let lowEnd):
            let value = unit == .kcal ? Amount.kcal(amount) : Amount.gallons(amount)
            return lowEnd ? "+\(value)" : "+\(value), high end only"
        case .expired: return "Not counted (expired)"
        case .untreatedWater(let gallons): return "+\(Amount.gallons(gallons)) beside water (not potable)"
        case .missingNutrition: return "Not counted: no calories"
        case .missingWaterVolume: return "Not counted: no gallons per item"
        case .excludedByKit: return "Not counted: inside a kit"
        case .noRunway(let category): return "No \(category.title.lowercased()) runway yet"
        case .unavailable: return "Not counted"
        }
    }

    /// "Garage › Shelf 2"
    static func path(_ status: LotStatus) -> String {
        status.locationChain.reversed().map(\.name).joined(separator: " › ")
    }

    /// The row's secondary line: "20 lb · best by Jun 2027".
    static func detailLine(_ status: LotStatus) -> String {
        var parts = [QuantityText.format(status.lot, product: status.product)]
        if let printed = status.lot.printedDate {
            parts.append("\((status.profile?.dateType ?? .bestBy).label.lowercased()) \(printed.monthYear)")
        } else if status.profile?.dateType == ShelfLifeDateType.none {
            parts.append("stored \(status.lot.acquiredDate.monthYear)")
        }
        return parts.joined(separator: " · ")
    }
}
