import Foundation
import GRDB
import HearthstockCore

/// A stored value that doesn't map back to a Core value (an unknown enum case, a malformed ID or date).
/// The schema's CHECK constraints make this unreachable for rows written by the app; it guards
/// against rows written by a newer build or by hand.
struct RecordMappingError: Error, Equatable, CustomStringConvertible {
    let table: String
    let column: String
    let value: String

    var description: String { "\(table).\(column) holds an invalid value: \(value)" }
}

/// How timestamps are stored: ISO 8601 UTC with milliseconds, e.g. `2026-01-31T10:20:30.123Z`.
/// This is the format the schema's column defaults produce, so the two never mix in one column.
enum StoredTimestamp {
    private static var style: Date.ISO8601FormatStyle {
        Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    }

    /// Rounds to the nearest millisecond. Whole seconds are formatted and the milliseconds appended
    /// as integers, because formatting a fractional `Date` truncates (`.1229999` → `.122`).
    static func string(from date: Date) -> String {
        let milliseconds = Int((date.timeIntervalSince1970 * 1000).rounded())
        let (seconds, fraction) = milliseconds.quotientAndRemainder(dividingBy: 1000)
        let wholeSeconds = fraction < 0 ? seconds - 1 : seconds
        let fractionMillis = fraction < 0 ? fraction + 1000 : fraction
        let base = Date(timeIntervalSince1970: Double(wholeSeconds)).formatted(Date.ISO8601FormatStyle())
        return base.dropLast() + String(format: ".%03dZ", fractionMillis)
    }

    static func date(from string: String) -> Date? {
        try? style.parse(string)
    }
}

/// A GRDB record for one table whose rows carry `createdAt` and `updatedAt`.
///
/// Records are plain column values (`String`, `Double`, `Bool`); mapping to and from Core types is
/// explicit on each record. Always write through `insert(_:clock:)`, `update(_:clock:)` or
/// `save(_:clock:)`: they stamp the timestamps from the injected clock. GRDB's own `insert(_:)`
/// leaves a freshly mapped record's nil timestamps unset, which the NOT NULL columns reject.
protocol StoredRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    var createdAt: Date? { get set }
    var updatedAt: Date? { get set }
}

extension StoredRecord {
    static func databaseDateEncodingStrategy(for column: String) -> DatabaseDateEncodingStrategy {
        .custom { StoredTimestamp.string(from: $0) }
    }

    static func databaseDateDecodingStrategy(for column: String) -> DatabaseDateDecodingStrategy {
        .custom { dbValue in
            String.fromDatabaseValue(dbValue).flatMap(StoredTimestamp.date(from:))
        }
    }

    /// Inserts the row with `createdAt` and `updatedAt` both set to the clock's now.
    func insert(_ db: Database, clock: StoreClock) throws {
        var stamped = self
        let now = clock.now()
        stamped.createdAt = now
        stamped.updatedAt = now
        try stamped.insert(db)
    }

    /// Updates the existing row, setting `updatedAt` to the clock's now. `createdAt` is never written.
    /// Throws if the row doesn't exist.
    func update(_ db: Database, clock: StoreClock) throws {
        var stamped = self
        stamped.updatedAt = clock.now()
        let columns = try stamped.databaseDictionary.keys.filter { $0 != "createdAt" }
        try stamped.update(db, columns: columns)
    }

    /// Updates the row if it exists, otherwise inserts it.
    func save(_ db: Database, clock: StoreClock) throws {
        if try exists(db) {
            try update(db, clock: clock)
        } else {
            try insert(db, clock: clock)
        }
    }
}

// MARK: - Column decoding

/// Raw column values to Core values, throwing `RecordMappingError` on anything unrecognised.
struct ColumnDecoder {
    let table: String

    func id<ID: EntityID>(_ column: String, _ value: String) throws -> ID {
        guard let uuid = UUID(uuidString: value) else { throw error(column, value) }
        return ID(rawValue: uuid)
    }

    func optionalID<ID: EntityID>(_ column: String, _ value: String?) throws -> ID? {
        try value.map { try id(column, $0) }
    }

    func `enum`<Value: RawRepresentable>(_ column: String, _ value: String) throws -> Value
    where Value.RawValue == String {
        guard let decoded = Value(rawValue: value) else { throw error(column, value) }
        return decoded
    }

    func optionalEnum<Value: RawRepresentable>(_ column: String, _ value: String?) throws -> Value?
    where Value.RawValue == String {
        try value.map { try `enum`(column, $0) }
    }

    func date(_ column: String, _ value: String) throws -> CalendarDate {
        guard let decoded = CalendarDate(iso: value) else { throw error(column, value) }
        return decoded
    }

    func optionalDate(_ column: String, _ value: String?) throws -> CalendarDate? {
        try value.map { try date(column, $0) }
    }

    private func error(_ column: String, _ value: String) -> RecordMappingError {
        RecordMappingError(table: table, column: column, value: value)
    }
}

extension EntityID {
    /// The stored form of an identifier: the canonical uppercase UUID string.
    var stored: String { rawValue.uuidString }
}
