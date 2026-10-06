import Foundation
import Testing
@testable import HearthstockCore

@Suite struct IdentifierTests {
    @Test func freshIDsAreUnique() {
        #expect(LotID() != LotID())
    }

    @Test func wrapsRawValue() {
        let uuid = UUID()
        #expect(SiteID(rawValue: uuid).rawValue == uuid)
        #expect(SiteID(rawValue: uuid) == SiteID(rawValue: uuid))
    }

    @Test func codableAsBareUUIDString() throws {
        let uuid = UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!
        let data = try JSONEncoder().encode([ProductID(rawValue: uuid)])
        #expect(String(decoding: data, as: UTF8.self) == #"["E621E1F8-C36C-495A-93FC-0C247A3E6E5F"]"#)
        #expect(try JSONDecoder().decode([ProductID].self, from: data) == [ProductID(rawValue: uuid)])
    }

    @Test func everyEntityHasAnID() {
        let uuid = UUID()
        #expect(SiteID(rawValue: uuid).rawValue == uuid)
        #expect(PersonID(rawValue: uuid).rawValue == uuid)
        #expect(LocationID(rawValue: uuid).rawValue == uuid)
        #expect(ProductID(rawValue: uuid).rawValue == uuid)
        #expect(LotID(rawValue: uuid).rawValue == uuid)
        #expect(KitID(rawValue: uuid).rawValue == uuid)
        #expect(KitTemplateID(rawValue: uuid).rawValue == uuid)
    }
}
