import HearthstockCore
import SwiftUI

/// A lot state as a word and an icon, never color alone (design.md §5).
struct StateBadge: View {
    let state: LotState

    var body: some View {
        Label {
            Text(state.title)
        } icon: {
            Image(systemName: state.symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(iconColor)
        }
        .labelStyle(BadgeLabelStyle())
        .font(.footnote.weight(.semibold))
        .foregroundStyle(textColor)
        .padding(.vertical, 4)
        .padding(.horizontal, 10)
        .background(background)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(state.title)
    }

    private var textColor: Color {
        switch state {
        case .good: .hsGood
        case .useSoon: .hsInk
        case .caution, .inspect: .hsAmber
        case .expired: .hsRed
        }
    }

    private var iconColor: Color {
        state == .useSoon ? .hsAmber : textColor
    }

    @ViewBuilder private var background: some View {
        switch state {
        case .good: Capsule().fill(Color.hsGoodBg)
        case .useSoon: Capsule().fill(Color.hsTrack)
        case .caution: Capsule().fill(Color.hsAmberBg)
        case .inspect: Capsule().strokeBorder(Color.hsAmber, lineWidth: 1.5)
        case .expired: Capsule().fill(Color.hsRedBg)
        }
    }
}

private struct BadgeLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon
            configuration.title
        }
    }
}

/// A 38 pt rounded-square icon tile (FocusRow, pickers).
struct IconTile: View {
    let symbol: String
    var foreground: Color = .hsTint
    var background: Color = .hsTintSoft

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(foreground)
            .frame(width: 38, height: 38)
            .background(background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityHidden(true)
    }
}

extension LotState {
    /// The tile colors a Focus next row uses for this state.
    var tileColors: (foreground: Color, background: Color) {
        switch self {
        case .good: (.hsGood, .hsGoodBg)
        case .useSoon: (.hsAmber, .hsTrack)
        case .caution, .inspect: (.hsAmber, .hsAmberBg)
        case .expired: (.hsRed, .hsRedBg)
        }
    }
}

/// A failed subscription, shown in place of a screen's content.
struct FeedFailureView: View {
    let message: String

    var body: some View {
        ContentUnavailableView {
            Label("Couldn't load your data", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message).textSelection(.enabled)
        }
    }
}

/// Loading, failure or content, by phase.
struct FeedContent<Content: View>: View {
    let phase: FeedPhase
    @ViewBuilder var content: () -> Content

    var body: some View {
        switch phase {
        case .loading: ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message): FeedFailureView(message: message)
        case .live: content()
        }
    }
}

/// Flag icons for a lot: missing date, power-dependent, humidity risk, not potable.
struct LotFlagIcons: View {
    let flags: Set<LotFlag>
    var notPotable = false

    var body: some View {
        HStack(spacing: 6) {
            if flags.contains(.missingDate) { flag("calendar.badge.exclamationmark", "No date") }
            if flags.contains(.powerDependent) { flag("bolt.slash", "Needs power") }
            if flags.contains(.humidityRisk) { flag("humidity", "Humid") }
            if notPotable { flag("drop.triangle", "Not potable") }
        }
        .font(.footnote)
        .foregroundStyle(Color.hsInk2)
    }

    private func flag(_ symbol: String, _ text: String) -> some View {
        Label(text, systemImage: symbol).labelStyle(.titleAndIcon).imageScale(.small)
    }
}
