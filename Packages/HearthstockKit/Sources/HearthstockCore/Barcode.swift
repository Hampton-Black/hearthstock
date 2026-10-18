import Foundation

/// Why a string isn't a barcode the app can store.
public enum BarcodeError: Error, Hashable, Sendable {
    /// Nothing left after removing spaces and dashes.
    case empty
    /// Something other than the digits 0–9.
    case nonDigits
    /// Not 8, 12, 13 or 14 digits (or a 14-digit case code, which isn't an item).
    case length(Int)
    /// The last digit doesn't match the others: a misread or a typo.
    case checkDigit
    /// The camera said UPC-E, but the code can't be one (UPC-E starts with 0 or 1).
    case unknownFormat
}

/// A retail barcode in one canonical form, so a scan and a hand-typed code for the same item compare equal.
///
/// UPC-A (12 digits), UPC-E (8, expanded to its UPC-A), EAN-13 and a 14-digit GTIN with a leading zero all become
/// the 13-digit GTIN. EAN-8 stays 8 digits. The check digit is always validated. Encodes as the bare string.
public struct Barcode: Hashable, Sendable, Codable, CustomStringConvertible {
    /// What the camera reported, for the one case it matters: an 8-digit code can be an EAN-8 or a UPC-E.
    public enum Symbology: Hashable, Sendable {
        case ean8
        case ean13
        case upcA
        case upcE
    }

    /// 13 digits, or 8 for an EAN-8.
    public let rawValue: String

    /// Normalizes `raw` from the camera or the keyboard. Spaces, dashes and other whitespace are ignored.
    ///
    /// An 8-digit code with no `symbology` (typed by hand) is read as a UPC-E when it starts with 0 and is a valid
    /// one, since those are common on small US packs; otherwise as an EAN-8, and failing that as a UPC-E starting
    /// with 1.
    public init(_ raw: String, symbology: Symbology? = nil) throws(BarcodeError) {
        let kept = raw.filter { !$0.isWhitespace && $0 != "-" }
        guard !kept.isEmpty else { throw .empty }
        guard kept.allSatisfy({ $0.isASCII && $0.isNumber }) else { throw .nonDigits }
        let digits = kept.map { Int($0.asciiValue! - 48) }

        switch digits.count {
        case 8:
            rawValue = try Self.eightDigit(digits, symbology: symbology)
        case 12:
            guard Self.hasValidCheckDigit(digits) else { throw .checkDigit }
            rawValue = "0" + kept
        case 13:
            guard Self.hasValidCheckDigit(digits) else { throw .checkDigit }
            rawValue = kept
        case 14 where digits[0] == 0:
            guard Self.hasValidCheckDigit(digits) else { throw .checkDigit }
            rawValue = String(kept.dropFirst())
        default:
            throw .length(digits.count)
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        do {
            try self.init(string)
        } catch {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "not a barcode: \(string) (\(error))")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var description: String { rawValue }

    // MARK: Rules

    private static func eightDigit(_ digits: [Int], symbology: Symbology?) throws(BarcodeError) -> String {
        let asEAN8 = hasValidCheckDigit(digits) ? string(digits) : nil
        let asUPCE = expandedUPCE(digits).map { "0" + string($0) }
        switch symbology {
        case .upcE?:
            guard digits[0] == 0 || digits[0] == 1 else { throw .unknownFormat }
            guard let asUPCE else { throw .checkDigit }
            return asUPCE
        case .ean8?, .ean13?, .upcA?:
            guard let asEAN8 else { throw .checkDigit }
            return asEAN8
        case nil:
            if digits[0] == 0, let asUPCE { return asUPCE }
            if let asEAN8 { return asEAN8 }
            if let asUPCE { return asUPCE }
            throw .checkDigit
        }
    }

    /// The UPC-A a UPC-E stands for, when the UPC-E's number system (0 or 1) and check digit are valid. The check
    /// digit is computed over the expanded code.
    private static func expandedUPCE(_ digits: [Int]) -> [Int]? {
        let system = digits[0], d = Array(digits[1...6]), check = digits[7]
        guard system == 0 || system == 1 else { return nil }
        let body: [Int]
        switch d[5] {
        case 0...2: body = [system, d[0], d[1], d[5], 0, 0, 0, 0, d[2], d[3], d[4]]
        case 3: body = [system, d[0], d[1], d[2], 0, 0, 0, 0, 0, d[3], d[4]]
        case 4: body = [system, d[0], d[1], d[2], d[3], 0, 0, 0, 0, 0, d[4]]
        default: body = [system, d[0], d[1], d[2], d[3], d[4], 0, 0, 0, 0, d[5]]
        }
        guard checkDigit(for: body) == check else { return nil }
        return body + [check]
    }

    /// GS1 mod-10: weights 3 and 1 alternating from the digit next to the check digit.
    private static func checkDigit(for payload: [Int]) -> Int {
        let sum = payload.reversed().enumerated().reduce(0) { sum, pair in
            sum + pair.element * (pair.offset.isMultiple(of: 2) ? 3 : 1)
        }
        return (10 - sum % 10) % 10
    }

    private static func hasValidCheckDigit(_ digits: [Int]) -> Bool {
        checkDigit(for: Array(digits.dropLast())) == digits.last
    }

    private static func string(_ digits: [Int]) -> String {
        String(digits.map { Character(String($0)) })
    }
}
