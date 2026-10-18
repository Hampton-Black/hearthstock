import Foundation
import Testing
@testable import HearthstockCore

@Suite struct BarcodeTests {
    @Test(arguments: [
        // UPC-A and its EAN-13 and GTIN-14 forms are one product.
        ("036000291452", "0036000291452"),
        ("0036000291452", "0036000291452"),
        ("00036000291452", "0036000291452"),
        // EAN-13 from outside North America.
        ("4006381333931", "4006381333931"),
        // EAN-8 stays 8 digits.
        ("96385074", "96385074"),
        // Spaces and dashes from a hand-typed code.
        ("0 36000 29145 2", "0036000291452"),
        ("036000-291452", "0036000291452"),
        (" 4006381333931\n", "4006381333931"),
    ])
    func normalizes(raw: String, expected: String) throws {
        #expect(try Barcode(raw).rawValue == expected)
    }

    /// UPC-E expands to its UPC-A, one pair for each rule the last of the six digits selects.
    @Test(arguments: [
        ("04252614", "0042100005264"),  // ends in 0–2: manufacturer digits, then four zeros
        ("01200003", "0012000000003"),
        ("01234133", "0012300000413"),  // ends in 3
        ("01234558", "0012345000058"),  // ends in 5–9
    ])
    func expandsUPCE(upcE: String, gtin: String) throws {
        #expect(try Barcode(upcE, symbology: .upcE).rawValue == gtin)
        #expect(try Barcode(String(gtin.dropFirst())).rawValue == gtin)
    }

    @Test func upcEAndItsUPCAFindTheSameProduct() throws {
        #expect(try Barcode("04252614", symbology: .upcE) == Barcode("042100005264"))
    }

    /// An 8-digit code can be an EAN-8 or a UPC-E. The camera says which; a typed code starting with 0 that's a valid
    /// UPC-E is one (they're common on small US packs), otherwise it's an EAN-8.
    @Test(arguments: [
        ("01234565", nil, "0012345000065"),
        ("01234565", Barcode.Symbology.upcE, "0012345000065"),
        ("01234565", Barcode.Symbology.ean8, "01234565"),
        ("96385074", nil, "96385074"),
        ("96385074", Barcode.Symbology.ean8, "96385074"),
    ] as [(String, Barcode.Symbology?, String)])
    func eightDigitCodes(raw: String, symbology: Barcode.Symbology?, expected: String) throws {
        #expect(try Barcode(raw, symbology: symbology).rawValue == expected)
    }

    @Test(arguments: [
        ("", BarcodeError.empty),
        (" - ", .empty),
        ("03600029145A", .nonDigits),
        ("ABC", .nonDigits),
        ("٠٣٦٠٠٠٢٩١٤٥٢", .nonDigits),  // Arabic-Indic digits aren't barcode digits
        ("12345", .length(5)),
        ("0360002914521", .checkDigit),  // 13 digits, wrong check
        ("036000291453", .checkDigit),
        ("96385075", .checkDigit),
        ("10036000291459", .length(14)),  // a case code (packaging indicator 1), not an item
        ("123456789012345", .length(15)),
    ])
    func refuses(raw: String, error: BarcodeError) {
        #expect(throws: error) { try Barcode(raw) }
    }

    @Test(arguments: [
        ("01234144", Barcode.Symbology.upcE),  // UPC-E with a bad check digit
        ("21234565", .upcE),  // UPC-E must start with 0 or 1
        ("01234567", .ean8),
    ])
    func refusesWithSymbology(raw: String, symbology: Barcode.Symbology) {
        #expect(throws: BarcodeError.self) { try Barcode(raw, symbology: symbology) }
    }

    @Test func normalizeIsIdempotent() throws {
        for raw in ["036000291452", "04252614", "96385074", "4006381333931"] {
            let once = try Barcode(raw)
            #expect(try Barcode(once.rawValue) == once)
        }
    }

    @Test func codableAsABareString() throws {
        let code = try Barcode("036000291452")
        let data = try JSONEncoder().encode(code)
        #expect(String(decoding: data, as: UTF8.self) == "\"0036000291452\"")
        #expect(try JSONDecoder().decode(Barcode.self, from: data) == code)
    }

    @Test func decodingRefusesAnInvalidCode() {
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(Barcode.self, from: Data("\"123\"".utf8)) }
    }
}
