import Foundation
import Testing
@testable import HearthstockCore

@Suite struct PrintedDateParserTests {
    static func day(_ year: Int, _ month: Int, _ day: Int) -> CalendarDate { CalendarDate(year: year, month: month, day: day)! }

    typealias Expected = (date: CalendarDate, precision: DateCandidate.Precision)

    static func dates(_ text: String) -> [Expected] {
        PrintedDateParser.candidates(in: text).map { ($0.date, $0.precision) }
    }

    @Test(arguments: [
        ("MAR 05 2027", day(2027, 3, 5)),
        ("Mar 5, 2027", day(2027, 3, 5)),
        ("05 MAR 27", day(2027, 3, 5)),
        ("05MAR2027", day(2027, 3, 5)),
        ("5 MARCH 2027", day(2027, 3, 5)),
        ("2027-03-05", day(2027, 3, 5)),
        ("SEP 30 2026", day(2026, 9, 30)),
    ])
    func unambiguousDays(text: String, date: CalendarDate) {
        for prefix in ["", "BEST BY ", "BB "] {
            let found = Self.dates(prefix + text)
            #expect(found.first?.date == date, "\(prefix + text)")
            #expect(found.first?.precision == .day)
        }
    }

    @Test(arguments: [
        ("MAR 2027", day(2027, 3, 1)),
        ("03/2027", day(2027, 3, 1)),
        ("BEST BY MAR 2027", day(2027, 3, 1)),
    ])
    func monthOnlyIsTheFirst(text: String, date: CalendarDate) {
        let found = Self.dates(text)
        #expect(found.count == 1)
        #expect(found.first?.date == date)
        #expect(found.first?.precision == .month)
    }

    /// 03/05/27 is March 5 in the US and May 3 elsewhere: both are offered, the earlier first (the safer mistake).
    @Test(arguments: [
        ("03/05/27", [day(2027, 3, 5), day(2027, 5, 3)]),
        ("05/03/27", [day(2027, 3, 5), day(2027, 5, 3)]),
        ("03.05.2027", [day(2027, 3, 5), day(2027, 5, 3)]),
        ("BEST BY 03 05 27", [day(2027, 3, 5), day(2027, 5, 3)]),
    ])
    func ambiguousNumericDatesOfferTheEarlierFirst(text: String, dates: [CalendarDate]) {
        #expect(Self.dates(text).map(\.date) == dates)
    }

    @Test func aNumericDateWithOneReadingHasOneCandidate() {
        #expect(Self.dates("12/25/26").map(\.date) == [Self.day(2026, 12, 25)])  // 25 can't be a month
        #expect(Self.dates("25/12/26").map(\.date) == [Self.day(2026, 12, 25)])
        #expect(Self.dates("07/07/27").map(\.date) == [Self.day(2027, 7, 7)])  // both readings agree
    }

    @Test(arguments: ["02/30/27", "13/13/27", "FEB 30 2027", "2027-02-29", "00/05/27"])
    func impossibleDatesAreDropped(text: String) {
        #expect(Self.dates(text).isEmpty)
    }

    @Test(arguments: ["L2304 14:32", "LOT 230414 1432", "14:32", "NET WT 15 OZ (425g)", "", "CA 12345"])
    func lotCodesTimesAndOtherNumbersAreNotDates(text: String) {
        #expect(Self.dates(text).isEmpty)
    }

    @Test func lotCodeNoiseAroundADate() {
        let found = Self.dates("L2304 14:32\nBEST BY MAR 05 2027\nP12")
        #expect(found.map(\.date) == [Self.day(2027, 3, 5)])
    }

    @Test(arguments: [
        ("BEST BY MAR 05 2027", ShelfLifeDateType.bestBy),
        ("BEST BEFORE 05 MAR 27", .bestBy),
        ("BEST IF USED BY 2027-03-05", .bestBy),
        ("BB 05MAR2027", .bestBy),
        ("USE BY MAR 05 2027", .useBy),
        ("EXP 03/2027", .useBy),
        ("MAR 05 2027", nil),
    ] as [(String, ShelfLifeDateType?)])
    func dateTypeWhenTheTextSaysIt(text: String, dateType: ShelfLifeDateType?) {
        #expect(PrintedDateParser.candidates(in: text).first?.dateType == dateType)
    }

    @Test func twoDigitYearsAreThisCentury() {
        #expect(Self.dates("05 MAR 99").first?.date == Self.day(2099, 3, 5))
        #expect(Self.dates("05 MAR 01").first?.date == Self.day(2001, 3, 5))
    }

    @Test func eachDateIsOfferedOnce() {
        #expect(Self.dates("MAR 05 2027 / 2027-03-05").map(\.date) == [Self.day(2027, 3, 5)])
    }
}
