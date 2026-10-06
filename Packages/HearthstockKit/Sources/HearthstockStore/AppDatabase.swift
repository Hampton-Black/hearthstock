import Foundation
import GRDB

/// The app's SQLite database: a GRDB writer with foreign keys on and every migration applied.
public struct AppDatabase: Sendable {
    /// Thread-safe GRDB connection. Repositories read and write through it.
    public let writer: any DatabaseWriter

    init(_ writer: any DatabaseWriter) throws {
        self.writer = writer
        try Self.migrator.migrate(writer)
    }

    /// A fresh, private in-memory database. For tests and previews.
    public static func inMemory() throws -> AppDatabase {
        try AppDatabase(DatabaseQueue(configuration: makeConfiguration()))
    }

    /// A WAL database file at `url`, creating its directory if missing.
    public static func onDisk(at url: URL = defaultURL) throws -> AppDatabase {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        return try AppDatabase(DatabasePool(path: url.path(percentEncoded: false), configuration: makeConfiguration()))
    }

    /// Application Support/Hearthstock/hearthstock.sqlite
    public static var defaultURL: URL {
        URL.applicationSupportDirectory
            .appending(path: "Hearthstock", directoryHint: .isDirectory)
            .appending(path: "hearthstock.sqlite", directoryHint: .notDirectory)
    }

    static func makeConfiguration() -> Configuration {
        var config = Configuration()
        config.foreignKeysEnabled = true
        return config
    }

    /// The single migrator. Migrations are append-only and registered in order; never edit one
    /// that has shipped. `eraseDatabaseOnSchemaChange` is deliberately not used.
    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerHearthstockMigrations()
        return migrator
    }
}
