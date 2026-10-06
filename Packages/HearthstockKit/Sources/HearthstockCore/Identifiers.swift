import Foundation

/// A typed identifier wrapping a UUID, so IDs of different entities can't be mixed up.
/// Encodes as a bare UUID string.
public protocol EntityID: Hashable, Sendable, Codable, CustomStringConvertible {
    var rawValue: UUID { get }
    init(rawValue: UUID)
}

extension EntityID {
    /// A fresh random identifier.
    public init() { self.init(rawValue: UUID()) }

    public init(from decoder: any Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(UUID.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var description: String { rawValue.uuidString }
}

public struct SiteID: EntityID {
    public let rawValue: UUID
    public init(rawValue: UUID) { self.rawValue = rawValue }
}

public struct PersonID: EntityID {
    public let rawValue: UUID
    public init(rawValue: UUID) { self.rawValue = rawValue }
}

public struct LocationID: EntityID {
    public let rawValue: UUID
    public init(rawValue: UUID) { self.rawValue = rawValue }
}

public struct ProductID: EntityID {
    public let rawValue: UUID
    public init(rawValue: UUID) { self.rawValue = rawValue }
}

public struct LotID: EntityID {
    public let rawValue: UUID
    public init(rawValue: UUID) { self.rawValue = rawValue }
}

public struct KitID: EntityID {
    public let rawValue: UUID
    public init(rawValue: UUID) { self.rawValue = rawValue }
}

public struct KitTemplateID: EntityID {
    public let rawValue: UUID
    public init(rawValue: UUID) { self.rawValue = rawValue }
}
