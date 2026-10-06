import Foundation
import GRDB
import Testing
@testable import HearthstockStore

@Suite struct AppDatabaseTests {
    @Test func inMemoryDatabaseMigratesCleanly() throws {
        let db = try AppDatabase.inMemory()
        let applied = try db.writer.read { try AppDatabase.migrator.appliedIdentifiers($0) }
        #expect(applied.sorted() == AppDatabase.migrator.migrations.sorted())
        let complete = try db.writer.read { try AppDatabase.migrator.hasCompletedMigrations($0) }
        #expect(complete)
    }

    @Test func foreignKeysAreEnforced() throws {
        let db = try AppDatabase.inMemory()
        try createScratchTables(db.writer)
        #expect(throws: DatabaseError.self) {
            try db.writer.write {
                try $0.execute(sql: "INSERT INTO scratchLot (id, locationId) VALUES ('lot', 'nowhere')")
            }
        }
        try db.writer.write {
            try $0.execute(sql: "INSERT INTO scratchLocation (id) VALUES ('shelf')")
            try $0.execute(sql: "INSERT INTO scratchLot (id, locationId) VALUES ('lot', 'shelf')")
        }
    }

    @Test func onDiskDatabaseReopensWithDataIntact() throws {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "AppDatabaseTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "nested/hearthstock.sqlite")

        let first = try AppDatabase.onDisk(at: url)
        #expect(first.writer is DatabasePool)
        let journalMode = try first.writer.read { try String.fetchOne($0, sql: "PRAGMA journal_mode") }
        #expect(journalMode == "wal")
        try createScratchTables(first.writer)
        try first.writer.write { try $0.execute(sql: "INSERT INTO scratchLocation (id) VALUES ('shelf')") }
        try first.writer.close()

        let second = try AppDatabase.onDisk(at: url)
        let ids = try second.writer.read { try String.fetchAll($0, sql: "SELECT id FROM scratchLocation") }
        #expect(ids == ["shelf"])
        let foreignKeys = try second.writer.read { try Bool.fetchOne($0, sql: "PRAGMA foreign_keys") }
        #expect(foreignKeys == true)
        try second.writer.close()
    }

    @Test func defaultURLIsInApplicationSupport() {
        let url = AppDatabase.defaultURL
        #expect(url.lastPathComponent == "hearthstock.sqlite")
        #expect(url.deletingLastPathComponent().lastPathComponent == "Hearthstock")
        #expect(url.deletingLastPathComponent().deletingLastPathComponent().standardizedFileURL
            == URL.applicationSupportDirectory.standardizedFileURL)
    }

    /// Stand-in tables until v1_initial lands (Task 2). Foreign keys are a connection setting,
    /// so any parent/child pair proves enforcement.
    private func createScratchTables(_ writer: any DatabaseWriter) throws {
        try writer.write { db in
            try db.execute(sql: """
                CREATE TABLE scratchLocation (id TEXT PRIMARY KEY NOT NULL);
                CREATE TABLE scratchLot (
                    id TEXT PRIMARY KEY NOT NULL,
                    locationId TEXT NOT NULL REFERENCES scratchLocation(id)
                );
                """)
        }
    }
}
