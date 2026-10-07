import SwiftUI
import UIKit

/// The design's color tokens (docs/design.md §1), each with a light and a dark value.
extension Color {
    static let hsBg = Color(light: 0xF6F1E9, dark: 0x17140F)
    static let hsCard = Color(light: 0xFFFDF9, dark: 0x25211B)
    static let hsInk = Color(light: 0x2B241E, dark: 0xF3ECE2)
    static let hsInk2 = Color(light: 0x5F554B, dark: 0xBCB09F)
    static let hsInk3 = Color(light: 0x776C61, dark: 0xA39784)
    static let hsSeparator = Color(light: 0xE6DED2, dark: 0x3A342C)
    static let hsTrack = Color(light: 0xE9E2D6, dark: 0x332E27)
    static let hsTint = Color(light: 0x2F5D50, dark: 0x86BBA6)
    static let hsTintSoft = Color(light: 0xE2ECE6, dark: 0x24352E)
    static let hsOnTint = Color(light: 0xFFFDF9, dark: 0x17140F)
    static let hsGood = Color(light: 0x2E6B4F, dark: 0x8CC7A5)
    static let hsGoodBg = Color(light: 0xE1EEE5, dark: 0x203328)
    static let hsAmber = Color(light: 0x8A5A00, dark: 0xF0BC5E)
    static let hsAmberBg = Color(light: 0xFBEACB, dark: 0x3A2E17)
    static let hsAmberLine = Color(light: 0xD9A441, dark: 0xC9973A)
    static let hsRed = Color(light: 0xA3241B, dark: 0xF2918A)
    static let hsRedBg = Color(light: 0xF7DFDB, dark: 0x41201C)
}

private extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(rgb: dark) : UIColor(rgb: light) })
    }
}

private extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1)
    }
}

extension View {
    /// Rounded, monospaced digits for numbers (design.md §2).
    func numeric() -> some View {
        fontDesign(.rounded).monospacedDigit()
    }

    /// A grouped list on the design's background, with card-colored rows.
    func hearthList() -> some View {
        listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.hsBg)
    }

    /// The dashboard's card: card color, 20 pt corners.
    func card(padding: CGFloat = 16) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.hsCard, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

/// Full-width primary button: 56 pt high, radius 16, `tint` fill.
struct PrimaryButtonStyle: ButtonStyle {
    var role: Role = .primary

    enum Role {
        case primary
        case secondary
        case destructive
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 56)
            .foregroundStyle(foreground)
            .background(background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }

    private var foreground: Color {
        switch role {
        case .primary: .hsOnTint
        case .secondary: .hsTint
        case .destructive: .hsRed
        }
    }

    private var background: Color {
        switch role {
        case .primary: .hsTint
        case .secondary: .hsTintSoft
        case .destructive: .hsCard
        }
    }
}
