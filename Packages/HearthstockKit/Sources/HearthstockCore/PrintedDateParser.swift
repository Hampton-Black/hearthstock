import Foundation

/// A printed date read off a package, for the date sheet to propose. Never saved without the person confirming it.
public struct DateCandidate: Hashable, Sendable {
    public enum Precision: Hashable, Sendable {
        case day
        /// Only a month was printed ("MAR 2027"): the date is the 1st, the earlier and safer end of the month.
        case month
    }

    public var date: CalendarDate
    public var precision: Precision
    /// The kind of date when the text says it ("BEST BY", "USE BY", "EXP").
    public var dateType: ShelfLifeDateType?

    public init(date: CalendarDate, precision: Precision, dateType: ShelfLifeDateType? = nil) {
        self.date = date
        self.precision = precision
        self.dateType = dateType
    }
}

/// Reads candidate printed dates out of recognized text (Live Text), as packages print them: `MAR 05 2027`,
/// `05 MAR 27`, `05MAR2027`, `03/05/27`, `03/2027`, `2027-03-05`, `MAR 2027`, `BEST BY 03 05 27`, with lot codes and
/// times around them.
///
/// Two-digit years are 20xx. Impossible dates are dropped. A numeric date that reads two ways (03/05/27: March 5 in
/// the US, May 3 elsewhere) gives both, the earlier first, since an earlier date is the safer mistake (Slice 4
/// Decision 18). Candidates come in the order they appear in the text, each date once.
public enum PrintedDateParser {
    public static func candidates(in text: String) -> [DateCandidate] {
        let upper = text.uppercased() as NSString
        var claimed: [NSRange] = []
        var found: [(location: Int, candidates: [DateCandidate])] = []

        for rule in rules {
            for match in rule.regex.matches(in: upper as String, range: NSRange(location: 0, length: upper.length)) {
                guard !claimed.contains(where: { NSIntersectionRange($0, match.range).length > 0 }) else { continue }
                let groups = (0..<match.numberOfRanges).map { index -> String? in
                    let range = match.range(at: index)
                    return range.location == NSNotFound ? nil : upper.substring(with: range)
                }
                let parsed = rule.parse(groups)
                guard !parsed.isEmpty else { continue }
                claimed.append(match.range)
                let dateType = rule.keywordGroup.flatMap { groups[$0] }.map(dateType(forKeyword:))
                    ?? keyword(before: match.range.location, in: upper)
                found.append((match.range.location, parsed.map {
                    DateCandidate(date: $0.date, precision: $0.precision, dateType: dateType)
                }))
            }
        }

        var seen: Set<CalendarDate> = []
        return found.sorted { $0.location < $1.location }
            .flatMap(\.candidates)
            .filter { seen.insert($0.date).inserted }
    }

    // MARK: Rules

    private typealias Parsed = (date: CalendarDate, precision: DateCandidate.Precision)

    private struct Rule: Sendable {
        let regex: NSRegularExpression
        /// The capture group holding a date-type keyword, when the pattern includes one.
        var keywordGroup: Int?
        let parse: @Sendable ([String?]) -> [Parsed]

        init(_ pattern: String, keywordGroup: Int? = nil, parse: @escaping @Sendable ([String?]) -> [Parsed]) {
            regex = try! NSRegularExpression(pattern: pattern)
            self.keywordGroup = keywordGroup
            self.parse = parse
        }
    }

    private static let month =
        "(JAN(?:UARY)?|FEB(?:RUARY)?|MAR(?:CH)?|APR(?:IL)?|MAY|JUNE?|JULY?|AUG(?:UST)?|SEP(?:T(?:EMBER)?)?|OCT(?:OBER)?|NOV(?:EMBER)?|DEC(?:EMBER)?)"
    private static let keywords = "(BEST\\s+IF\\s+USED\\s+BY|BEST\\s+BEFORE|BEST\\s+BY|\\bBB\\b|USE\\s+BY|\\bEXP(?:IRES|IRY)?\\b)"

    /// In priority order: once a stretch of text is read as a date, later rules skip it.
    private static let rules: [Rule] = [
        // 2027-03-05
        Rule("(?<!\\d)(\\d{4})-(\\d{1,2})-(\\d{1,2})(?!\\d)") { g in
            day(year: g[1], month: g[2], day: g[3])
        },
        // MAR 05 2027, Mar 5, 2027
        Rule("\\b\(month)\\.?\\s*(\\d{1,2})(?:ST|ND|RD|TH)?,?\\s+(\\d{4}|\\d{2})(?!\\d)") { g in
            day(year: g[3], month: monthNumber(g[1]), day: g[2])
        },
        // 05 MAR 27, 05MAR2027, 5 MARCH 2027
        Rule("(?<!\\d)(\\d{1,2})\\s*\(month)\\.?\\s*(\\d{4}|\\d{2})(?!\\d)") { g in
            day(year: g[3], month: monthNumber(g[2]), day: g[1])
        },
        // BEST BY 03 05 27: spaced numbers only count after a date keyword.
        Rule("\(keywords)[\\s:.\\-]{0,3}(\\d{1,2})\\s+(\\d{1,2})\\s+(\\d{4}|\\d{2})(?!\\d)", keywordGroup: 1) { g in
            ambiguous(g[2], g[3], year: g[4])
        },
        // 03/05/27, 03.05.2027, 03-05-27 (one separator throughout)
        Rule("(?<![\\d:/.])(\\d{1,2})([/.\\-])(\\d{1,2})\\2(\\d{4}|\\d{2})(?![\\d:/.])") { g in
            ambiguous(g[1], g[3], year: g[4])
        },
        // MAR 2027
        Rule("\\b\(month)\\.?\\s*(\\d{4})(?!\\d)") { g in
            monthOnly(year: g[2], month: monthNumber(g[1]))
        },
        // 03/2027
        Rule("(?<![\\d/.\\-])(\\d{1,2})[/\\-](\\d{4})(?![\\d/])") { g in
            monthOnly(year: g[2], month: g[1].flatMap { Int($0) })
        },
    ]

    // MARK: Pieces

    private static func year(_ text: String?) -> Int? {
        guard let text, let value = Int(text) else { return nil }
        if text.count == 2 { return 2000 + value }
        return (1990...2099).contains(value) ? value : nil
    }

    private static func day(year text: String?, month: Int?, day dayText: String?) -> [Parsed] {
        guard let year = year(text), let month, let day = dayText.flatMap({ Int($0) }),
              let date = CalendarDate(year: year, month: month, day: day)
        else { return [] }
        return [(date, .day)]
    }

    private static func day(year: String?, month: String?, day: String?) -> [Parsed] {
        self.day(year: year, month: month.flatMap { Int($0) }, day: day)
    }

    private static func monthOnly(year text: String?, month: Int?) -> [Parsed] {
        guard let year = year(text), let month, let date = CalendarDate(year: year, month: month, day: 1) else { return [] }
        return [(date, .month)]
    }

    /// Month/day (US) and day/month: every valid reading, earlier first, each once.
    private static func ambiguous(_ first: String?, _ second: String?, year text: String?) -> [Parsed] {
        guard let year = year(text), let a = first.flatMap({ Int($0) }), let b = second.flatMap({ Int($0) }) else {
            return []
        }
        let readings = [CalendarDate(year: year, month: a, day: b), CalendarDate(year: year, month: b, day: a)]
            .compactMap { $0 }
        return Array(Set(readings)).sorted().map { ($0, .day) }
    }

    private static let monthNumbers: [String: Int] = [
        "JAN": 1, "FEB": 2, "MAR": 3, "APR": 4, "MAY": 5, "JUN": 6, "JUL": 7, "AUG": 8, "SEP": 9, "OCT": 10,
        "NOV": 11, "DEC": 12,
    ]

    private static func monthNumber(_ name: String?) -> Int? {
        name.flatMap { monthNumbers[String($0.prefix(3))] }
    }

    private static let keywordRegex = try! NSRegularExpression(pattern: keywords)

    /// The date-type keyword right before `location` (only spaces, colons, dots or dashes between).
    private static func keyword(before location: Int, in text: NSString) -> ShelfLifeDateType? {
        let window = NSRange(location: 0, length: location)
        guard let match = keywordRegex.matches(in: text as String, range: window).last else { return nil }
        let gap = text.substring(with: NSRange(
            location: match.range.upperBound, length: location - match.range.upperBound))
        guard gap.allSatisfy({ $0.isWhitespace || ":.-".contains($0) }) else { return nil }
        return dateType(forKeyword: text.substring(with: match.range))
    }

    /// "EXP" reads as use by, the stricter of the two.
    private static func dateType(forKeyword keyword: String) -> ShelfLifeDateType {
        keyword.hasPrefix("USE") || keyword.hasPrefix("EXP") ? .useBy : .bestBy
    }
}
