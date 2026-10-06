import GRDB
import HearthstockCore

/// Placeholder so the target compiles and links GRDB. Schema and repositories arrive in Slice 2.
public enum HearthstockStore {
    public static func makeInMemoryDatabase() throws -> DatabaseQueue {
        try DatabaseQueue()
    }
}
