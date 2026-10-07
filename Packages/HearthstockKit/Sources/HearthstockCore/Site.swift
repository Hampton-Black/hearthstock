import Foundation

/// An independent place with its own runway (Main house, Bug-out cabin).
public struct Site: Hashable, Sendable, Codable, Identifiable {
    /// The spec's default Use soon notice window.
    public static let defaultNoticeWindowDays = 30

    public let id: SiteID
    public var name: String
    /// How many days before its printed date a lot turns Use soon. A positive whole number; the spec's
    /// "per household" setting.
    public var noticeWindowDays: Int

    public init(id: SiteID = SiteID(), name: String, noticeWindowDays: Int = Site.defaultNoticeWindowDays) {
        self.id = id
        self.name = name
        self.noticeWindowDays = noticeWindowDays
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, noticeWindowDays
    }

    /// A site encoded before the notice window existed decodes with the default.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(SiteID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        noticeWindowDays = try container.decodeIfPresent(Int.self, forKey: .noticeWindowDays)
            ?? Site.defaultNoticeWindowDays
    }
}

/// An occupant of a site, with daily calorie and water needs.
public struct Person: Hashable, Sendable, Codable, Identifiable {
    public static let defaultKcalPerDay: Double = 2000
    public static let defaultWaterGalPerDay: Double = 1.0

    public let id: PersonID
    public var siteID: SiteID
    public var name: String
    public var kcalPerDay: Double
    public var waterGalPerDay: Double

    public init(
        id: PersonID = PersonID(),
        siteID: SiteID,
        name: String,
        kcalPerDay: Double = Person.defaultKcalPerDay,
        waterGalPerDay: Double = Person.defaultWaterGalPerDay
    ) {
        self.id = id
        self.siteID = siteID
        self.name = name
        self.kcalPerDay = kcalPerDay
        self.waterGalPerDay = waterGalPerDay
    }
}
