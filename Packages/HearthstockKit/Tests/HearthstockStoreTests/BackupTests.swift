import Foundation
import GRDB
import HearthstockCore
import Synchronization
import Testing
@testable import HearthstockStore

private let t0 = Date(timeIntervalSince1970: 1_767_225_600)

/// A clock that advances a second per call, so rows get distinct, known timestamps.
private func tickingClock() -> StoreClock {
    let ticks = Mutex(0)
    return StoreClock { t0.addingTimeInterval(Double(ticks.withLock { $0 += 1; return $0 })) }
}

/// The sample pantry plus a product override and a lot override, in a database written with a ticking clock.
private func populatedDatabase() async throws -> (db: AppDatabase, fixture: PantryFixture) {
    let fixture = try PantryFixture.load()
    let db = try AppDatabase.inMemory()
    let clock = tickingClock()
    try await fixture.populate(db, clock: clock)
    let overrides = GRDBShelfLifeOverrideRepository(database: db, clock: clock)
    try await overrides.save(ShelfLifeOverride(extensionMonths: 6), for: fixture.products[0].id)
    try await overrides.save(ShelfLifeOverride(dateType: .useBy, rotationMonths: 12), for: fixture.lots[0].id)
    return (db, fixture)
}

private func json(_ data: Data) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
}

/// The document with `exportedAt` removed, for comparing two exports.
private func withoutExportedAt(_ data: Data) throws -> NSDictionary {
    var object = try json(data)
    object["exportedAt"] = nil
    return object as NSDictionary
}

private func rowCount(_ db: AppDatabase) async throws -> Int {
    try await db.writer.read { db in
        try ["site", "person", "product", "location", "kit", "lot", "shelf_life_override"]
            .map { try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \($0)") ?? 0 }
            .reduce(0, +)
    }
}

@Suite struct BackupTests {
    @Test func exportIsAVersionedDocumentWithISODates() async throws {
        let (db, fixture) = try await populatedDatabase()
        let exportTime = Date(timeIntervalSince1970: 1_800_000_000.5)
        let data = try await GRDBBackup(database: db, clock: .fixed(exportTime)).export()
        let document = try json(data)

        #expect(document["formatVersion"] as? Int == 2)
        #expect(document["exportedAt"] as? String == "2027-01-15T08:00:00.500Z")
        #expect((document["sites"] as? [Any])?.count == 1)
        #expect((document["lots"] as? [Any])?.count == fixture.lots.count)
        #expect((document["shelfLifeOverrides"] as? [Any])?.count == 2)

        let lot = try #require((document["lots"] as? [[String: Any]])?.first { $0["id"] as? String == fixture.lots[0].id.stored })
        #expect(lot["acquiredDate"] as? String == fixture.lots[0].acquiredDate.iso)
        let created = try #require(lot["createdAt"] as? String)
        #expect(created.hasPrefix("2026-01-01T00:00:") && created.hasSuffix("Z"))
    }

    @Test func exportImportExportIsIdenticalApartFromExportedAt() async throws {
        let (source, _) = try await populatedDatabase()
        let first = try await GRDBBackup(database: source, clock: .fixed(t0)).export()

        let target = try AppDatabase.inMemory()
        try await GRDBBackup(database: target).import(first)
        let second = try await GRDBBackup(database: target, clock: .fixed(t0.addingTimeInterval(3600))).export()

        #expect(try withoutExportedAt(first) == withoutExportedAt(second))
        #expect(first != second)
    }

    @Test func importedDatabaseGivesTheSameRunwayAsTheFixture() async throws {
        let (source, fixture) = try await populatedDatabase()
        let data = try await GRDBBackup(database: source).export()
        let target = try AppDatabase.inMemory()
        try await GRDBBackup(database: target).import(data)

        let profiles = try ShelfLifeProfileTable.bundledDefaults()
        let before = try await GRDBRunwayInputsLoader(database: source).load(siteID: fixture.site.id)
        let after = try await GRDBRunwayInputsLoader(database: target).load(siteID: fixture.site.id)

        #expect(after == before)
        #expect(
            RunwayCalculator.runway(for: after, profiles: profiles, on: fixture.today)
                == RunwayCalculator.runway(for: before, profiles: profiles, on: fixture.today))
        // Archived lots and kit links come back too.
        let lots = try await GRDBLotRepository(database: target).list(siteID: fixture.site.id, includeArchived: true)
        #expect(Set(lots) == Set(fixture.lots))
    }

    @Test func emptyDatabaseRoundTrips() async throws {
        let source = try AppDatabase.inMemory()
        let data = try await GRDBBackup(database: source, clock: .fixed(t0)).export()
        let target = try AppDatabase.inMemory()
        try await GRDBBackup(database: target).import(data)

        #expect(try await rowCount(target) == 0)
        let again = try await GRDBBackup(database: target, clock: .fixed(t0)).export()
        #expect(try withoutExportedAt(data) == withoutExportedAt(again))
    }

    @Test func importIntoANonEmptyDatabaseFailsAndChangesNothing() async throws {
        let (source, _) = try await populatedDatabase()
        let data = try await GRDBBackup(database: source).export()

        let target = try AppDatabase.inMemory()
        _ = try await GRDBSiteRepository(database: target).ensureDefaultSite()
        let before = try await GRDBBackup(database: target, clock: .fixed(t0)).export()

        await #expect(throws: BackupError.databaseNotEmpty) {
            try await GRDBBackup(database: target).import(data)
        }
        let after = try await GRDBBackup(database: target, clock: .fixed(t0)).export()
        #expect(before == after)

        // Importing the same file twice is the same refusal.
        let restored = try AppDatabase.inMemory()
        try await GRDBBackup(database: restored).import(data)
        await #expect(throws: BackupError.databaseNotEmpty) {
            try await GRDBBackup(database: restored).import(data)
        }
    }

    @Test(arguments: [0, 3, 99, -1])
    func unknownFormatVersionFailsCleanly(version: Int) async throws {
        let (source, _) = try await populatedDatabase()
        var document = try json(await GRDBBackup(database: source).export())
        document["formatVersion"] = version
        let data = try JSONSerialization.data(withJSONObject: document)

        let target = try AppDatabase.inMemory()
        await #expect(throws: BackupError.unsupportedFormatVersion(version)) {
            try await GRDBBackup(database: target).import(data)
        }
        #expect(try await rowCount(target) == 0)
    }

    @Test func aVersionFromTheFutureIsRefusedBeforeItsBodyIsRead() async throws {
        let data = Data(#"{"formatVersion": 3, "somethingNew": [1, 2, 3]}"#.utf8)
        let target = try AppDatabase.inMemory()
        await #expect(throws: BackupError.unsupportedFormatVersion(3)) {
            try await GRDBBackup(database: target).import(data)
        }
    }

    @Test(arguments: [
        "not json at all",
        "[]",
        #"{"exportedAt": "2026-01-01T00:00:00.000Z"}"#,
        #"{"formatVersion": 1}"#,
        #"{"formatVersion": 1, "exportedAt": "yesterday", "sites": [], "people": [], "products": [], "locations": [], "kits": [], "lots": [], "shelfLifeOverrides": []}"#,
    ])
    func unreadableFilesFailCleanly(text: String) async throws {
        let target = try AppDatabase.inMemory()
        do {
            try await GRDBBackup(database: target).import(Data(text.utf8))
            Issue.record("import should have failed")
        } catch let error as BackupError {
            guard case .invalidDocument = error else { throw error }
        }
        #expect(try await rowCount(target) == 0)
    }

    @Test func aFailedImportLeavesNothingBehind() async throws {
        let (source, fixture) = try await populatedDatabase()
        var document = try json(await GRDBBackup(database: source).export())
        // The last table written is lots, so everything before it is already in the transaction when this
        // one lot (pointing at a location that isn't in the file) is rejected.
        var lots = try #require(document["lots"] as? [[String: Any]])
        lots[lots.count - 1]["locationId"] = LocationID().stored
        document["lots"] = lots
        let data = try JSONSerialization.data(withJSONObject: document)

        let target = try AppDatabase.inMemory()
        do {
            try await GRDBBackup(database: target).import(data)
            Issue.record("import should have failed")
        } catch let error as BackupError {
            guard case .invalidDocument = error else { throw error }
        }
        #expect(try await rowCount(target) == 0)

        // The database is still usable, and the intact file imports into it.
        try await GRDBBackup(database: target).import(GRDBBackup(database: source).export())
        let lotsBack = try await GRDBLotRepository(database: target).list(siteID: fixture.site.id, includeArchived: true)
        #expect(lotsBack.count == fixture.lots.count)
    }

    @Test func aKitLinkToAMissingKitIsRejectedAtCommit() async throws {
        let (source, _) = try await populatedDatabase()
        var document = try json(await GRDBBackup(database: source).export())
        var locations = try #require(document["locations"] as? [[String: Any]])
        locations[0]["kitId"] = KitID().stored
        document["locations"] = locations
        let data = try JSONSerialization.data(withJSONObject: document)

        let target = try AppDatabase.inMemory()
        await #expect(throws: BackupError.self) {
            try await GRDBBackup(database: target).import(data)
        }
        #expect(try await rowCount(target) == 0)
    }

    @Test func locationsInAnyOrderImport() async throws {
        let (source, _) = try await populatedDatabase()
        var document = try json(await GRDBBackup(database: source, clock: .fixed(t0)).export())
        let reordered = try #require(document["locations"] as? [[String: Any]])
        // Children before parents.
        document["locations"] = reordered.sorted { ($0["parentId"] != nil ? 0 : 1) < ($1["parentId"] != nil ? 0 : 1) }
        let data = try JSONSerialization.data(withJSONObject: document)

        let target = try AppDatabase.inMemory()
        try await GRDBBackup(database: target).import(data)
        let again = try await GRDBBackup(database: target, clock: .fixed(t0)).export()
        let original = try await GRDBBackup(database: source, clock: .fixed(t0)).export()
        #expect(try withoutExportedAt(again) == withoutExportedAt(original))
    }
}
