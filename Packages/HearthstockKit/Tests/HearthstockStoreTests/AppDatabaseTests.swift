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
        try db.writer.write {
            try $0.execute(sql: """
                INSERT INTO site (id, name) VALUES ('home', 'Home');
                INSERT INTO product (id, name, category, role, unitKind, shelfLifeProfileKey)
                    VALUES ('rice', 'Rice', 'food', 'supply', 'mass', 'dry-grain');
                """)
        }
        #expect(throws: DatabaseError.self) {
            try db.writer.write {
                try $0.execute(sql: """
                    INSERT INTO lot (id, siteId, productId, locationId, quantity, acquiredDate)
                    VALUES ('lot', 'home', 'rice', 'nowhere', 1, '2026-01-01')
                    """)
            }
        }
        try db.writer.write {
            try $0.execute(sql: "INSERT INTO location (id, siteId, name) VALUES ('shelf', 'home', 'Shelf')")
            try $0.execute(sql: """
                INSERT INTO lot (id, siteId, productId, locationId, quantity, acquiredDate)
                VALUES ('lot', 'home', 'rice', 'shelf', 1, '2026-01-01')
                """)
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
        try first.writer.write { try $0.execute(sql: "INSERT INTO site (id, name) VALUES ('home', 'Home')") }
        try first.writer.close()

        let second = try AppDatabase.onDisk(at: url)
        let ids = try second.writer.read { try String.fetchAll($0, sql: "SELECT id FROM site") }
        #expect(ids == ["home"])
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
}
