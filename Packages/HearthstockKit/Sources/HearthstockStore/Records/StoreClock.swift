import Foundation

/// The source of "now" for write timestamps. Injected so tests stay deterministic.
public struct StoreClock: Sendable {
    private let provider: @Sendable () -> Date

    public init(_ now: @escaping @Sendable () -> Date) {
        self.provider = now
    }

    public func now() -> Date { provider() }

    /// The wall clock. The only place HearthstockStore reads `Date()`.
    public static let system = StoreClock { Date() }

    /// Always returns `date`.
    public static func fixed(_ date: Date) -> StoreClock {
        StoreClock { date }
    }
}
