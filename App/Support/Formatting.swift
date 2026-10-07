import Foundation
import HearthstockCore
import enum HearthstockCore.Category

/// Display text for Core values. Wording lives here; Core returns data.

// MARK: - Days (Decision 3)

/// A runway range as whole days, rounded down: "12–19", "12" when both ends round the same, "under 1" below a day.
struct DaysText: Equatable {
    var number: String
    var unit: String

    var full: String { "\(number) \(unit)" }

    init(_ range: RunwayRange) {
        let low = Int(max(0, range.low).rounded(.down))
        let high = Int(max(0, range.high).rounded(.down))
        if high < 1 {
            number = "under 1"
            unit = "day"
        } else if low == high {
            number = "\(low)"
            unit = low == 1 ? "day" : "days"
        } else {
            number = "\(low)–\(high)"
            unit = "days"
        }
    }

    /// Whole days, rounded down: "9".
    static func low(_ range: RunwayRange) -> Int { Int(max(0, range.low).rounded(.down)) }
}

// MARK: - Numbers and quantities

enum Amount {
    /// Up to `fraction` decimals, trailing zeros dropped, grouped: "3.17", "20", "1,630".
    static func text(_ value: Double, fraction: Int = 2) -> String {
        value.formatted(.number.precision(.fractionLength(0...fraction)))
    }

    static func kcal(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(0)))) kcal"
    }

    static func gallons(_ value: Double) -> String { "\(text(value, fraction: 1)) gal" }
}

extension QuantityUnit {
    /// The short label a picker or a quantity shows.
    var symbol: String {
        switch self {
        case .pound: "lb"
        case .ounce: "oz"
        case .kilogram: "kg"
        case .gram: "g"
        case .gallon: "gal"
        case .quart: "qt"
        case .liter: "L"
        case .milliliter: "mL"
        case .fluidOunce: "fl oz"
        case .wattHour: "Wh"
        case .kilowattHour: "kWh"
        case .milliampHour: "mAh"
        case .count: "items"
        }
    }

    /// Units a person picks from when entering an amount of this kind, base unit first. mAh needs a voltage,
    /// which this slice doesn't ask for, so energy offers Wh and kWh only.
    static func entryUnits(for kind: UnitKind) -> [QuantityUnit] {
        switch kind {
        case .mass: [.pound, .ounce, .kilogram, .gram]
        case .volume: [.gallon, .liter, .milliliter, .fluidOunce, .quart]
        case .energy: [.wattHour, .kilowattHour]
        case .count: [.count]
        }
    }
}

enum QuantityText {
    /// "20 lb", "3.17 gal", "6 items" ("1 item").
    static func format(_ value: Double, _ unit: QuantityUnit) -> String {
        if unit == .count {
            return "\(Amount.text(value)) \(value == 1 ? "item" : "items")"
        }
        return "\(Amount.text(value)) \(unit.symbol)"
    }

    static func format(_ lot: Lot, product: Product?) -> String {
        format(lot.quantity, product?.baseUnit ?? .count)
    }
}

// MARK: - Dates

extension CalendarDate {
    /// Today on the device's calendar.
    static func today(calendar: Calendar = .current, now: Date = Date()) -> CalendarDate {
        let parts = calendar.dateComponents([.year, .month, .day], from: now)
        return CalendarDate(year: parts.year ?? 1970, month: parts.month ?? 1, day: parts.day ?? 1)
            ?? CalendarDate(year: 1970, month: 1, day: 1)!
    }

    /// Midnight UTC on this day, for formatting and for date pickers. Always paired with `utcCalendar`, so the day
    /// never shifts with the device's time zone.
    var utcDate: Date {
        Self.utcCalendar.date(from: DateComponents(year: year, month: month, day: day)) ?? Date(timeIntervalSince1970: 0)
    }

    init(utcDate date: Date) {
        let parts = Self.utcCalendar.dateComponents([.year, .month, .day], from: date)
        self = CalendarDate(year: parts.year ?? 1970, month: parts.month ?? 1, day: parts.day ?? 1)
            ?? CalendarDate(year: 1970, month: 1, day: 1)!
    }

    /// A local-calendar `Date` at noon on this day, for SwiftUI's `DatePicker`, which works in the device's zone.
    var pickerDate: Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? Date()
    }

    init(pickerDate date: Date) {
        self = CalendarDate.today(now: date)
    }

    static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func formatted(_ style: Date.FormatStyle) -> String {
        var style = style
        style.timeZone = TimeZone(identifier: "UTC")!
        style.calendar = Self.utcCalendar
        return utcDate.formatted(style)
    }

    /// "Jun 2027"
    var monthYear: String { formatted(.dateTime.month(.abbreviated).year()) }
    /// "Jan 12, 2025"
    var medium: String { formatted(.dateTime.month(.abbreviated).day().year()) }
}

// MARK: - Domain names

/// Core's `Category`, named so it can't collide with the Objective-C runtime's `Category` type.
typealias SupplyCategory = Category

extension SupplyCategory {
    var title: String {
        switch self {
        case .food: "Food"
        case .water: "Water"
        case .power: "Power"
        case .medical: "Medical"
        case .tools: "Tools"
        case .hygiene: "Hygiene"
        case .other: "Other"
        }
    }

    var symbol: String {
        switch self {
        case .food: "fork.knife"
        case .water: "drop"
        case .power: "bolt"
        case .medical: "cross.case"
        case .tools: "wrench.and.screwdriver"
        case .hygiene: "hands.sparkles"
        case .other: "shippingbox"
        }
    }
}

extension UnitKind {
    var title: String {
        switch self {
        case .mass: "Mass"
        case .volume: "Volume"
        case .energy: "Energy"
        case .count: "Count"
        }
    }

    /// "lb", "gal", "Wh", "item": what one base unit is called after "per".
    var perUnit: String { self == .count ? "item" : baseUnit.symbol }
}

extension ClimateClass {
    var title: String {
        switch self {
        case .coolDry: "Cool and dry"
        case .rootCellar: "Root cellar"
        case .climateControlled: "Climate controlled"
        case .insulatedUnconditioned: "Insulated, unconditioned"
        case .hot: "Hot / unconditioned"
        case .vehicle: "Vehicle"
        case .refrigerated: "Refrigerated"
        case .frozen: "Frozen"
        }
    }

    /// Short form for tags: "Hot", "Cool and dry".
    var shortTitle: String {
        switch self {
        case .hot: "Hot"
        case .insulatedUnconditioned: "Insulated"
        default: title
        }
    }

    /// Example spots from the spec's climate table.
    var examples: String {
        switch self {
        case .coolDry: "Basement, interior closet, insulated pantry"
        case .rootCellar: "Earth-sheltered, usually humid"
        case .climateControlled: "Living space, conditioned room"
        case .insulatedUnconditioned: "Insulated garage or shed"
        case .hot: "Uninsulated garage, attic, outdoor shed"
        case .vehicle: "Car kit, truck bed box"
        case .refrigerated: "Fridge · needs power"
        case .frozen: "Chest freezer · needs power"
        }
    }

    var multiplierText: String {
        defaultWindowMultiplier.map { "\(Amount.text($0))×" } ?? "Per item"
    }
}

extension Packaging {
    var title: String {
        switch self {
        case .none: "None"
        case .mylarO2: "Mylar + O₂ absorber"
        case .bucket: "Bucket"
        case .stabilized: "Stabilized"
        }
    }
}

extension Humidity {
    var title: String {
        switch self {
        case .dry: "Dry"
        case .humid: "Humid"
        }
    }
}

extension LotState {
    var title: String {
        switch self {
        case .good: "Good"
        case .useSoon: "Use soon"
        case .caution: "Caution"
        case .inspect: "Inspect"
        case .expired: "Expired"
        }
    }

    var symbol: String {
        switch self {
        case .good: "checkmark"
        case .useSoon: "clock"
        case .caution: "arrow.triangle.2.circlepath"
        case .inspect: "magnifyingglass"
        case .expired: "xmark"
        }
    }
}

extension ShelfLifeDateType {
    /// How a printed date of this type reads: "Best by", "Use by", "Dated".
    var label: String {
        switch self {
        case .bestBy: "Best by"
        case .useBy: "Use by"
        case .none: "Dated"
        }
    }
}

extension Person {
    var needsText: String {
        "\(Amount.text(kcalPerDay, fraction: 0)) kcal · \(Amount.text(waterGalPerDay)) gal a day"
    }
}
