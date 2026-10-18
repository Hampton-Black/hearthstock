import Foundation

/// Turns the scanner's continuous stream of codes in frame into deliberate scans. Pure: time is passed in.
///
/// - A code is accepted once, then ignored while it stays in frame.
/// - A code that leaves the frame and comes back within `returnGap` is still the same scan; after longer, it's a new
///   one.
/// - A code seen anew after it was added is a repeat ("Scanned again"), not a new scan.
/// - Each accepted scan holds the debouncer until `resume()`: while a card or the next screen is showing, other
///   codes are ignored, so a can sliding past in the background doesn't replace what you're reading. A code that
///   arrived while holding and is still in frame after `resume()` is the next scan (you've moved on to the next
///   can); one that has left is forgotten.
public struct ScanDebouncer: Hashable, Sendable {
    public enum Event: Hashable, Sendable {
        case scan(Barcode)
        case `repeat`(Barcode)
    }

    /// How long a code must be out of frame before seeing it again counts as a new scan.
    public static let returnGap: TimeInterval = 1.5

    /// True from an accepted scan until `resume()`.
    public private(set) var isHolding = false
    private var inFrame: Set<Barcode> = []
    private var leftAt: [Barcode: Date] = [:]
    private var added: Set<Barcode> = []
    /// Codes that arrived while holding, in arrival order.
    private var waiting: [Barcode] = []

    public init() {}

    /// Feeds every code in frame right now. Call it on each scanner update, including when the last code leaves
    /// (an empty set). Returns at most one event; when several codes appear at once, the first by value wins.
    public mutating func sighted(_ codes: Set<Barcode>, at time: Date) -> Event? {
        for code in inFrame.subtracting(codes) {
            leftAt[code] = time
        }
        let arriving = codes.subtracting(inFrame).sorted { $0.rawValue < $1.rawValue }
        inFrame = codes

        var event: Event?
        for code in arriving {
            if let left = leftAt.removeValue(forKey: code), time.timeIntervalSince(left) < Self.returnGap {
                continue  // back from a moment out of frame: the same scan
            }
            if isHolding || event != nil {
                if !waiting.contains(code) { waiting.append(code) }
            } else {
                event = self.event(for: code)
            }
        }
        waiting.removeAll { !inFrame.contains($0) }
        if event == nil, !isHolding, !waiting.isEmpty {
            event = self.event(for: waiting.removeFirst())
        }
        if event != nil { isHolding = true }
        return event
    }

    private func event(for code: Barcode) -> Event {
        added.contains(code) ? .repeat(code) : .scan(code)
    }

    /// The code was saved, so seeing it anew is a repeat.
    public mutating func added(_ code: Barcode) {
        added.insert(code)
    }

    /// The card or screen for the last scan closed: accept the next code.
    public mutating func resume() {
        isHolding = false
    }
}
