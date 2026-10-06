import Foundation

/// A day on the proleptic Gregorian calendar, with no time or time zone.
///
/// Used for printed, expiry and acquired dates. Stored and encoded as ISO `YYYY-MM-DD`.
/// Arithmetic is pure integer math, so results never shift with the device's time zone.
public struct CalendarDate: Hashable, Sendable {
    public let year: Int
    public let month: Int
    public let day: Int

    /// Returns nil unless the components name a real date in years 1...9999.
    public init?(year: Int, month: Int, day: Int) {
        guard (1...9999).contains(year),
              (1...12).contains(month),
              (1...Self.daysInMonth(year: year, month: month)).contains(day)
        else { return nil }
        self.year = year
        self.month = month
        self.day = day
    }

    /// Parses exactly `YYYY-MM-DD` with ASCII digits; anything else is nil.
    public init?(iso: String) {
        let bytes = Array(iso.utf8)
        guard bytes.count == 10, bytes[4] == UInt8(ascii: "-"), bytes[7] == UInt8(ascii: "-") else { return nil }
        func number(_ range: Range<Int>) -> Int? {
            var value = 0
            for byte in bytes[range] {
                guard (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte) else { return nil }
                value = value * 10 + Int(byte - UInt8(ascii: "0"))
            }
            return value
        }
        guard let year = number(0..<4), let month = number(5..<7), let day = number(8..<10) else { return nil }
        self.init(year: year, month: month, day: day)
    }

    /// The ISO `YYYY-MM-DD` form.
    public var iso: String {
        func pad(_ value: Int, _ width: Int) -> String {
            let digits = String(value)
            return String(repeating: "0", count: max(0, width - digits.count)) + digits
        }
        return "\(pad(year, 4))-\(pad(month, 2))-\(pad(day, 2))"
    }

    /// Adds calendar months, clamping the day to the end of the target month
    /// (Jan 31 + 1 month = Feb 28, or Feb 29 in a leap year).
    public func adding(months: Int) -> CalendarDate {
        let monthIndex = year * 12 + (month - 1) + months
        let newYear = monthIndex >= 0 ? monthIndex / 12 : (monthIndex - 11) / 12
        let newMonth = monthIndex - newYear * 12 + 1
        let newDay = min(day, Self.daysInMonth(year: newYear, month: newMonth))
        return Self(unchecked: newYear, newMonth, newDay)
    }

    public func adding(days: Int) -> CalendarDate {
        Self(dayNumber: dayNumber + days)
    }

    /// Whole days from this date to `other`; negative when `other` is earlier.
    public func days(until other: CalendarDate) -> Int {
        other.dayNumber - dayNumber
    }

    // MARK: Internals

    private init(unchecked year: Int, _ month: Int, _ day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    static func isLeapYear(_ year: Int) -> Bool {
        (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
    }

    static func daysInMonth(year: Int, month: Int) -> Int {
        switch month {
        case 2: isLeapYear(year) ? 29 : 28
        case 4, 6, 9, 11: 30
        default: 31
        }
    }

    /// Days since 1970-01-01 (Howard Hinnant's days_from_civil).
    private var dayNumber: Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yearOfEra = y - era * 400
        let shiftedMonth = month > 2 ? month - 3 : month + 9
        let dayOfYear = (153 * shiftedMonth + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

    /// Inverse of `dayNumber` (Howard Hinnant's civil_from_days).
    private init(dayNumber: Int) {
        let z = dayNumber + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let dayOfEra = z - era * 146_097
        let yearOfEra = (dayOfEra - dayOfEra / 1460 + dayOfEra / 36524 - dayOfEra / 146_096) / 365
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let shiftedMonth = (5 * dayOfYear + 2) / 153
        let day = dayOfYear - (153 * shiftedMonth + 2) / 5 + 1
        let month = shiftedMonth < 10 ? shiftedMonth + 3 : shiftedMonth - 9
        self.init(unchecked: yearOfEra + era * 400 + (month <= 2 ? 1 : 0), month, day)
    }
}

extension CalendarDate: Comparable {
    public static func < (lhs: CalendarDate, rhs: CalendarDate) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}

extension CalendarDate: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let date = CalendarDate(iso: string) else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Expected a valid YYYY-MM-DD date, got \(string)")
        }
        self = date
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(iso)
    }
}

extension CalendarDate: CustomStringConvertible {
    public var description: String { iso }
}
