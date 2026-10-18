import Foundation

/// Where a lot stands on a given day. Derived, never stored.
public enum LotState: String, Hashable, Sendable, Codable, CaseIterable {
    case good
    /// Within the notice window before the printed date: a nudge, not a warning. Counts fully toward runway.
    case useSoon
    /// Past best-by, inside the extension window: eat or rotate first.
    case caution
    /// Final 20% of the window: check before use.
    case inspect
    /// Past the window or any use-by date; excluded from runway.
    case expired
}

/// Notes about a lot that don't change its dates.
public enum LotFlag: String, Hashable, Sendable, Codable, CaseIterable {
    /// No printed date and not marked "no printed date", so nothing ages it; the UI nudges for one.
    case missingDate
    /// Marked "no printed date" and aged from an estimate (acquired date + the profile's `rotationMonths`), so every
    /// date shown for it says "Est.".
    case estimatedDate
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
    /// The window's phases, for explaining a state and drawing a timeline. All nil when nothing dates the lot.
    public var timeline: Timeline?

    /// When each phase of the lot's window starts. Good runs from `start` through `goodThrough`; Use soon (if any)
    /// is the end of that span; Caution (if `hasCaution`) follows until `inspectFrom`; the window ends on
    /// `usableBy`.
    public struct Timeline: Hashable, Sendable {
        /// The printed date for a printed-date window, else the acquired date.
        public var goodThrough: CalendarDate
        public var useSoonFrom: CalendarDate?
        public var inspectFrom: CalendarDate
        public var hasCaution: Bool
        /// True when the window is measured from the printed date (otherwise from the acquired date).
        public var fromPrintedDate: Bool
        /// True when the window is an estimate for a package with no printed date (`LotFlag.estimatedDate`).
        public var isEstimate: Bool
    }

    public init(state: LotState, usableBy: CalendarDate?, flags: Set<LotFlag> = [], timeline: Timeline? = nil) {
        self.state = state
        self.usableBy = usableBy
        self.flags = flags
        self.timeline = timeline
    }
}

public enum ShelfLifeEvaluator {
    /// Share of a window, at its end, that is Inspect rather than Good or Caution.
    static let inspectFraction = 0.2

    /// Evaluates a lot on `today` under the climate and humidity it's stored in.
    ///
    /// `windowMultiplier`, when set, replaces the climate class's multiplier (a location's override).
    /// The class still decides power dependence.
    ///
    /// `noticeWindowDays` is the site's Use soon window: a lot whose window starts at its printed date is Use soon
    /// from that many days before the printed date through the printed date itself. Zero (the default) turns
    /// Use soon off, which is how Slice 1 evaluated lots.
    ///
    /// Refrigerated and frozen lots are evaluated as climate controlled and flagged power-dependent
    /// until per-product cold-storage profiles exist.
    public static func evaluate(
        _ lot: Lot,
        profile: ShelfLifeProfile,
        climate: ClimateClass,
        humidity: Humidity = .dry,
        windowMultiplier: Double? = nil,
        noticeWindowDays: Int = 0,
        on today: CalendarDate
    ) -> ShelfLifeEvaluation {
        var flags: Set<LotFlag> = []
        let multiplier: Double
        if let value = climate.defaultWindowMultiplier {
            multiplier = windowMultiplier ?? value
        } else {
            multiplier = windowMultiplier ?? ClimateClass.climateControlled.defaultWindowMultiplier ?? 1.0
            flags.insert(.powerDependent)
        }
        if humidity == .humid && lot.packaging == .none {
            flags.insert(.humidityRisk)
        }

        guard var window = window(for: lot, profile: profile, multiplier: multiplier) else {
            if profile.dateType != .none && lot.printedDate == nil && !lot.noPrintedDate {
                flags.insert(.missingDate)
            }
            return ShelfLifeEvaluation(state: .good, usableBy: nil, flags: flags)
        }
        if noticeWindowDays > 0, window.startsAtPrintedDate {
            window.useSoonFrom = window.goodThrough.adding(days: -noticeWindowDays)
        }
        if window.isEstimate { flags.insert(.estimatedDate) }
        let timeline = ShelfLifeEvaluation.Timeline(
            goodThrough: window.goodThrough, useSoonFrom: window.useSoonFrom, inspectFrom: window.inspectFrom,
            hasCaution: window.hasCaution, fromPrintedDate: window.startsAtPrintedDate, isEstimate: window.isEstimate)
        return ShelfLifeEvaluation(
            state: window.state(on: today), usableBy: window.usableBy, flags: flags, timeline: timeline)
    }

    /// A span of days ending on `usableBy`. Good through `goodThrough` (Use soon from `useSoonFrom`, when set),
    /// then Caution (if `hasCaution`) until the last 20%, then Inspect, then Expired.
    struct Window {
        var goodThrough: CalendarDate
        var usableBy: CalendarDate
        var hasCaution: Bool
        /// True when `goodThrough` is the lot's printed date, so the notice window applies.
        var startsAtPrintedDate = false
        /// True for the estimate given to a dated profile's lot marked "no printed date".
        var isEstimate = false
        var useSoonFrom: CalendarDate?

        func state(on today: CalendarDate) -> LotState {
            if today <= goodThrough {
                if let useSoonFrom, today >= useSoonFrom { return .useSoon }
                return .good
            }
            if today > usableBy { return .expired }
            if today >= inspectFrom { return .inspect }
            return hasCaution ? .caution : .good
        }

        /// First day of the final 20% of the window.
        var inspectFrom: CalendarDate {
            let length = goodThrough.days(until: usableBy)
            let inspectDays = Int((Double(length) * inspectFraction).rounded(.up))
            return usableBy.adding(days: 1 - inspectDays)
        }
    }

    /// The lot's window, or nil when nothing dates it.
    ///
    /// A best-by lot ages from the longest of its printed-date window and its packaged life (Mylar + O₂ or
    /// bucket). A best-by or use-by lot marked "no printed date" also gets an estimate, acquired date +
    /// `rotationMonths` scaled by climate like every profile month, and the longest window still wins, so packaging
    /// that outlasts the estimate dates the lot. Profiles with date type none rotate from the acquired date,
    /// unscaled, unless packaging gives a window.
    static func window(for lot: Lot, profile: ShelfLifeProfile, multiplier: Double) -> Window? {
        var candidates: [Window] = []
        switch profile.dateType {
        case .useBy:
            if let printed = lot.printedDate {
                return Window(goodThrough: printed, usableBy: printed, hasCaution: false, startsAtPrintedDate: true)
            }

        case .bestBy:
            if let printed = lot.printedDate {
                let end = scaled(from: printed, months: profile.extensionMonths ?? 0, by: multiplier)
                candidates.append(Window(goodThrough: printed, usableBy: end, hasCaution: true, startsAtPrintedDate: true))
            }
            if let packaged = packagedWindow(for: lot, profile: profile, multiplier: multiplier) {
                candidates.append(packaged)
            }

        case .none:
            if let packaged = packagedWindow(for: lot, profile: profile, multiplier: multiplier) {
                candidates.append(packaged)
            } else if let months = profile.rotationMonths {
                let end = lot.acquiredDate.adding(months: months)
                candidates.append(Window(goodThrough: lot.acquiredDate, usableBy: end, hasCaution: false))
            }
        }

        if profile.dateType != .none, lot.printedDate == nil, lot.noPrintedDate, let months = profile.rotationMonths {
            let end = scaled(from: lot.acquiredDate, months: months, by: multiplier)
            candidates.append(Window(goodThrough: lot.acquiredDate, usableBy: end, hasCaution: false, isEstimate: true))
        }
        // On a tie the earlier candidate (printed date, then packaging) wins, so an estimate is used only when it's
        // strictly longer.
        return candidates.reduce(nil) { best, next in
            guard let best else { return next }
            return next.usableBy > best.usableBy ? next : best
        }
    }

    private static func packagedWindow(for lot: Lot, profile: ShelfLifeProfile, multiplier: Double) -> Window? {
        guard lot.packaging == .mylarO2 || lot.packaging == .bucket, let months = profile.packagedLifeMonths else {
            return nil
        }
        let end = scaled(from: lot.acquiredDate, months: months, by: multiplier)
        return Window(goodThrough: lot.acquiredDate, usableBy: end, hasCaution: false)
    }

    /// `start` plus `months`, with the span in days scaled by `multiplier` and rounded down.
    static func scaled(from start: CalendarDate, months: Int, by multiplier: Double) -> CalendarDate {
        let days = start.days(until: start.adding(months: months))
        return start.adding(days: Int((Double(days) * multiplier).rounded(.down)))
    }
}
