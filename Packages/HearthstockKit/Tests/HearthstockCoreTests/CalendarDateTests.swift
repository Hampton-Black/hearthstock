import Foundation
import Testing
@testable import HearthstockCore

@Suite struct CalendarDateTests {
    private func date(_ iso: String) -> CalendarDate {
        guard let date = CalendarDate(iso: iso) else {
            Issue.record("Invalid fixture date \(iso)")
            return CalendarDate(year: 2000, month: 1, day: 1)!
        }
        return date
    }

    // MARK: ISO round-trip

    @Test(arguments: ["2026-10-06", "2024-02-29", "1999-12-31", "0001-01-01", "9999-12-31"])
    func isoRoundTrip(iso: String) {
        #expect(CalendarDate(iso: iso)?.iso == iso)
    }

    @Test func isoIsZeroPadded() {
        #expect(CalendarDate(year: 2026, month: 3, day: 7)?.iso == "2026-03-07")
    }

    @Test func codableEncodesAsISOString() throws {
        let value = date("2026-10-06")
        let data = try JSONEncoder().encode([value])
        #expect(String(decoding: data, as: UTF8.self) == #"["2026-10-06"]"#)
        let decoded = try JSONDecoder().decode([CalendarDate].self, from: data)
        #expect(decoded == [value])
    }

    @Test func decodingInvalidStringThrows() {
        let data = Data(#"["2026-02-30"]"#.utf8)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode([CalendarDate].self, from: data)
        }
    }

    // MARK: Invalid strings

    @Test(arguments: [
        "", "2026", "2026-10", "2026-1-06", "2026-10-6", "26-10-06",
        "2026/10/06", "2026-10-06T00:00:00Z", " 2026-10-06", "2026-10-06 ",
        "2026-00-10", "2026-13-01", "2026-01-00", "2026-01-32",
        "2026-02-29", "1900-02-29", "2026-04-31", "abcd-ef-gh", "+026-10-06", "2026-+1-06",
        "２０２６-10-06",
    ])
    func invalidStringsRejected(iso: String) {
        #expect(CalendarDate(iso: iso) == nil)
    }

    @Test func invalidComponentsRejected() {
        #expect(CalendarDate(year: 2026, month: 2, day: 29) == nil)
        #expect(CalendarDate(year: 0, month: 1, day: 1) == nil)
        #expect(CalendarDate(year: 2024, month: 2, day: 29) != nil)
        #expect(CalendarDate(year: 2000, month: 2, day: 29) != nil)
    }

    // MARK: Comparison

    @Test func comparable() {
        #expect(date("2025-12-31") < date("2026-01-01"))
        #expect(date("2026-01-31") < date("2026-02-01"))
        #expect(date("2026-02-01") < date("2026-02-02"))
        #expect(!(date("2026-02-02") < date("2026-02-02")))
    }

    // MARK: Adding months

    @Test(arguments: [
        ("2026-01-15", 1, "2026-02-15"),
        ("2026-01-31", 1, "2026-02-28"),
        ("2024-01-31", 1, "2024-02-29"),
        ("2000-01-31", 1, "2000-02-29"),
        ("2100-01-31", 1, "2100-02-28"),
        ("2024-02-29", 12, "2025-02-28"),
        ("2024-02-29", 48, "2028-02-29"),
        ("2026-03-31", 1, "2026-04-30"),
        ("2026-12-31", 2, "2027-02-28"),
        ("2026-11-30", 3, "2027-02-28"),
        ("2026-03-31", -1, "2026-02-28"),
        ("2026-01-15", -1, "2025-12-15"),
        ("2026-10-06", 0, "2026-10-06"),
        ("2026-10-06", 24, "2028-10-06"),
        ("2026-10-06", -24, "2024-10-06"),
    ])
    func addingMonths(start: String, months: Int, expected: String) {
        #expect(date(start).adding(months: months) == date(expected))
    }

    // MARK: Adding days

    @Test(arguments: [
        ("2026-10-06", 0, "2026-10-06"),
        ("2026-10-06", 1, "2026-10-07"),
        ("2026-12-31", 1, "2027-01-01"),
        ("2027-01-01", -1, "2026-12-31"),
        ("2024-02-28", 1, "2024-02-29"),
        ("2026-02-28", 1, "2026-03-01"),
        ("2026-01-01", 365, "2027-01-01"),
        ("2024-01-01", 366, "2025-01-01"),
        ("2026-03-08", 1, "2026-03-09"),
        ("2026-11-01", 1, "2026-11-02"),
    ])
    func addingDays(start: String, days: Int, expected: String) {
        #expect(date(start).adding(days: days) == date(expected))
    }

    // MARK: Day differences

    @Test(arguments: [
        ("2026-10-06", "2026-10-06", 0),
        ("2026-10-06", "2026-10-07", 1),
        ("2026-10-07", "2026-10-06", -1),
        ("2026-12-31", "2027-01-01", 1),
        ("2025-12-15", "2026-01-15", 31),
        ("2026-01-01", "2027-01-01", 365),
        ("2024-01-01", "2025-01-01", 366),
        ("2023-12-31", "2028-01-01", 1462),
        ("2027-01-01", "2026-12-31", -1),
        ("2026-03-08", "2026-03-09", 1),
    ])
    func daysUntil(from: String, to: String, expected: Int) {
        #expect(date(from).days(until: date(to)) == expected)
    }

    @Test func addingDaysInvertsDaysUntil() {
        let start = date("2024-02-29")
        for offset in stride(from: -1000, through: 1000, by: 37) {
            #expect(start.days(until: start.adding(days: offset)) == offset)
        }
    }
}
