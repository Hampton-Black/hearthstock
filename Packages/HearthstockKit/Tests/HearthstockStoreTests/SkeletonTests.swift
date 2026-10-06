import Testing
@testable import HearthstockStore

@Test func inMemoryDatabaseOpens() throws {
    let db = try HearthstockStore.makeInMemoryDatabase()
    let one = try db.read { try Int.fetchOne($0, sql: "SELECT 1") }
    #expect(one == 1)
}
