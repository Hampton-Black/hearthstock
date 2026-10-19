import Foundation

/// Turns the scanner's continuous stream of codes in frame into deliberate scans. Pure: time is passed in.
///
/// - A code is accepted once, then ignored while it stays in frame.
/// - A code that leaves the frame and comes back within `returnGap` is still the same scan; after longer, it's a new
///   one. The code accepted last needs `sameCodeGap` instead: the scanner can lose a code for a moment while it's
///   held still, and that mustn't read as a second scan.
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
    /// The same for the code accepted last.
    public static let sameCodeGap: TimeInterval = 3

    /// True from an accepted scan until `resume()`.
    public private(set) var isHolding = false
    private var inFrame: Set<Barcode> = []
    private var leftAt: [Barcode: Date] = [:]
    private var added: Set<Barcode> = []
    /// Codes that arrived while holding, in arrival order. Never the code being held.
    private var waiting: [Barcode] = []
    private var lastAccepted: Barcode?

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
            let gap = code == lastAccepted ? Self.sameCodeGap : Self.returnGap
            if let left = leftAt.removeValue(forKey: code), time.timeIntervalSince(left) < gap {
                continue  // back from a moment out of frame: the same scan
            }
            if isHolding && code == lastAccepted {
                continue  // the code on the card, back in view: still the same scan
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
        if let event { accept(event) }
        return event
    }

    private mutating func accept(_ event: Event) {
        isHolding = true
        switch event {
        case .scan(let code), .repeat(let code): lastAccepted = code
        }
    }

    private func event(for code: Barcode) -> Event {
        added.contains(code) ? .repeat(code) : .scan(code)
    }

    /// A code typed by hand ("Type a barcode"): the same path as a camera read, except that it's never "in frame".
    /// Nil while holding.
    public mutating func typed(_ code: Barcode) -> Event? {
        guard !isHolding else { return nil }
        let event = event(for: code)
        accept(event)
        return event
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
