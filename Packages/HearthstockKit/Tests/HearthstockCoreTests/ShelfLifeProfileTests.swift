import Foundation
import Testing
@testable import HearthstockCore

@Suite struct ShelfLifeProfileTests {
    typealias Row = (key: String, dateType: ShelfLifeDateType, extension: Int?, packaged: Int?, rotation: Int?)

    /// The reviewed starting table from the Task 4 bead. Changing a value here means changing a default: flag it.
    static let expectedDefaults: [Row] = [
        ("canned_low_acid", .bestBy, 24, nil, nil),
        ("canned_high_acid", .bestBy, 12, nil, nil),
        ("white_rice", .bestBy, 24, 120, nil),
        ("dried_beans", .bestBy, 24, 120, nil),
        ("wheat_berries", .bestBy, 24, 120, nil),
        ("rolled_oats", .bestBy, 12, 60, nil),
        ("pasta_dry", .bestBy, 12, 60, nil),
        ("brown_rice", .bestBy, 3, nil, nil),
        ("flour", .bestBy, 6, nil, nil),
        ("cooking_oil", .bestBy, 3, nil, nil),
        ("peanut_butter", .bestBy, 6, nil, nil),
        ("freeze_dried", .bestBy, 12, nil, nil),
        ("mre", .bestBy, 12, nil, nil),
        ("bottled_water", .bestBy, 24, nil, nil),
        ("stored_tap_water", .none, nil, nil, 6),
        ("honey_salt_sugar", .none, nil, nil, nil),
        ("infant_formula", .useBy, 0, nil, nil),
        ("medication", .useBy, 0, nil, nil),
        ("unknown_food", .bestBy, 6, nil, nil),
    ]

    @Test func bundledDefaultsLoad() throws {
        let table = try ShelfLifeProfileTable.bundledDefaults()
        #expect(table.profiles.count == Self.expectedDefaults.count)
    }

    @Test(arguments: expectedDefaults.map { $0.key })
    func bundledDefaultMatchesReviewedTable(key: String) throws {
        let row = try #require(Self.expectedDefaults.first { $0.key == key })
        let profile = try #require(try ShelfLifeProfileTable.bundledDefaults()[ShelfLifeProfileKey(rawValue: key)])
        #expect(profile.key.rawValue == key)
        #expect(profile.dateType == row.dateType)
        #expect(profile.extensionMonths == row.extension)
        #expect(profile.packagedLifeMonths == row.packaged)
        #expect(profile.rotationMonths == row.rotation)
    }

    @Test func useByProfilesGetNoExtension() throws {
        for profile in try ShelfLifeProfileTable.bundledDefaults().profiles where profile.dateType == .useBy {
            #expect(profile.extensionMonths == 0, "\(profile.key)")
        }
    }

    @Test func unknownKeyReturnsNil() throws {
        #expect(try ShelfLifeProfileTable.bundledDefaults()["no_such_profile"] == nil)
    }

    @Test func duplicateKeysAreRejected() {
        let json = Data("""
        [{"key": "flour", "name": "Flour", "dateType": "bestBy", "extensionMonths": 6},
         {"key": "flour", "name": "Flour", "dateType": "bestBy", "extensionMonths": 9}]
        """.utf8)
        #expect(throws: ShelfLifeProfileTable.LoadError.duplicateKey("flour")) {
            try ShelfLifeProfileTable(jsonData: json)
        }
    }

    @Test func everyBundledProfileHasAName() throws {
        for profile in try ShelfLifeProfileTable.bundledDefaults().profiles {
            #expect(!profile.name.trimmingCharacters(in: .whitespaces).isEmpty, "\(profile.key)")
            #expect(profile.name != profile.key.rawValue, "\(profile.key) reads as a key")
        }
    }

    @Test(arguments: [
        #"[{"key": "flour", "dateType": "bestBy", "extensionMonths": 6}]"#,
        #"[{"key": "flour", "name": "  ", "dateType": "bestBy", "extensionMonths": 6}]"#,
    ])
    func aProfileWithoutANameIsRejected(json: String) {
        #expect(throws: ShelfLifeProfileTable.LoadError.missingName("flour")) {
            try ShelfLifeProfileTable(jsonData: Data(json.utf8))
        }
    }

    @Test func overridesKeepTheProfileName() throws {
        let profile = try #require(try ShelfLifeProfileTable.bundledDefaults()["white_rice"])
        #expect(ShelfLifeOverride(extensionMonths: 1).applied(to: profile).name == "White rice")
    }

    @Test func unknownDateTypeIsRejected() {
        let json = Data(#"[{"key": "flour", "dateType": "sellBy"}]"#.utf8)
        #expect(throws: DecodingError.self) { try ShelfLifeProfileTable(jsonData: json) }
    }

    @Test func profileRoundTripsThroughJSON() throws {
        let profile = ShelfLifeProfile(key: "white_rice", dateType: .bestBy, extensionMonths: 24, packagedLifeMonths: 120)
        #expect(try JSONDecoder().decode(ShelfLifeProfile.self, from: JSONEncoder().encode(profile)) == profile)
    }
}
