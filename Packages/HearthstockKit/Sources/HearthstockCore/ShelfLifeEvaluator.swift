import Foundation

/// Where a lot stands on a given day. Derived, never stored.
public enum LotState: String, Hashable, Sendable, Codable, CaseIterable {
    case good
    /// Past best-by, inside the extension window: eat or rotate first.
    case caution
    /// Final 20% of the window: check before use.
    case inspect
    /// Past the window or any use-by date; excluded from runway.
    case expired
}

/// Notes about a lot that don't change its dates.
public enum LotFlag: String, Hashable, Sendable, Codable, CaseIterable {
    /// No printed date and nothing else to age it by; the UI can nudge for one.
    case missingDate
    /// Stored refrigerated or frozen, so it lasts only while power does.
    case powerDependent
    /// Unsealed packaging (cans, paper, cardboard) in a humid location.
    case humidityRisk
}

public struct ShelfLifeEvaluation: Hashable, Sendable {
    public var state: LotState
    /// Last usable day, inclusive; nil when nothing dates the lot.
    public var usableBy: CalendarDate?
    public var flags: Set<LotFlag>

    public init(state: LotState, usableBy: CalendarDate?, flags: Set<LotFlag> = []) {
        self.state = state
        self.usableBy = usableBy
        self.flags = flags
    }
}

public enum ShelfLifeEvaluator {
    /// Share of a window, at its end, that is Inspect rather than Good or Caution.
    static let inspectFraction = 0.2

    /// Evaluates a lot on `today` under the climate and humidity it's stored in.
    ///
    /// Refrigerated and frozen lots are evaluated as climate controlled and flagged power-dependent
    /// until per-product cold-storage profiles exist.
    public static func evaluate(
        _ lot: Lot,
        profile: ShelfLifeProfile,
        climate: ClimateClass,
        humidity: Humidity = .dry,
        on today: CalendarDate
    ) -> ShelfLifeEvaluation {
        var flags: Set<LotFlag> = []
        let multiplier: Double
        if let value = climate.defaultWindowMultiplier {
            multiplier = value
        } else {
            multiplier = ClimateClass.climateControlled.defaultWindowMultiplier ?? 1.0
            flags.insert(.powerDependent)
        }
        if humidity == .humid && lot.packaging == .none {
            flags.insert(.humidityRisk)
        }

        guard let window = window(for: lot, profile: profile, multiplier: multiplier) else {
            if profile.dateType != .none && lot.printedDate == nil {
                flags.insert(.missingDate)
            }
            return ShelfLifeEvaluation(state: .good, usableBy: nil, flags: flags)
        }
        return ShelfLifeEvaluation(state: window.state(on: today), usableBy: window.usableBy, flags: flags)
    }

    /// A span of days ending on `usableBy`. Good through `goodThrough`, then Caution (if
    /// `hasCaution`) until the last 20%, then Inspect, then Expired.
    struct Window {
        var goodThrough: CalendarDate
        var usableBy: CalendarDate
        var hasCaution: Bool

        func state(on today: CalendarDate) -> LotState {
            if today <= goodThrough { return .good }
            if today > usableBy { return .expired }
            let length = goodThrough.days(until: usableBy)
            let inspectDays = Int((Double(length) * inspectFraction).rounded(.up))
            let firstInspectDay = usableBy.adding(days: 1 - inspectDays)
            if today >= firstInspectDay { return .inspect }
            return hasCaution ? .caution : .good
        }
    }

    static func window(for lot: Lot, profile: ShelfLifeProfile, multiplier: Double) -> Window? {
        switch profile.dateType {
        case .useBy:
            guard let printed = lot.printedDate else { return nil }
            return Window(goodThrough: printed, usableBy: printed, hasCaution: false)

        case .bestBy, .none:
            var candidates: [Window] = []
            if profile.dateType == .bestBy, let printed = lot.printedDate {
                let end = scaled(from: printed, months: profile.extensionMonths ?? 0, by: multiplier)
                candidates.append(Window(goodThrough: printed, usableBy: end, hasCaution: true))
            }
            if lot.packaging == .mylarO2 || lot.packaging == .bucket, let months = profile.packagedLifeMonths {
                let end = scaled(from: lot.acquiredDate, months: months, by: multiplier)
                candidates.append(Window(goodThrough: lot.acquiredDate, usableBy: end, hasCaution: false))
            }
            if candidates.isEmpty, lot.printedDate == nil || profile.dateType == .none,
               let months = profile.rotationMonths
            {
                let end = lot.acquiredDate.adding(months: months)
                candidates.append(Window(goodThrough: lot.acquiredDate, usableBy: end, hasCaution: false))
            }
            return candidates.max { $0.usableBy < $1.usableBy }
        }
    }

    /// `start` plus `months`, with the span in days scaled by `multiplier` and rounded down.
    static func scaled(from start: CalendarDate, months: Int, by multiplier: Double) -> CalendarDate {
        let days = start.days(until: start.adding(months: months))
        return start.adding(days: Int((Double(days) * multiplier).rounded(.down)))
    }
}
