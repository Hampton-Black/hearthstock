import HearthstockCore
import SwiftUI

/// Walk-Summary: what the walk added, what it did to the runway, and the lots still needing a date.
struct WalkSummaryView: View {
    let model: PantryWalkModel
    let walkAnother: (LocationID) -> Void
    let finish: () -> Void

    @Environment(AppRouter.self) private var router
    @State private var openLot: LotRef?

    private struct LotRef: Identifiable {
        let id: LotID
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Image(systemName: "checkmark")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Color.hsOnTint)
                    .frame(width: 64, height: 64)
                    .background(Color.hsTint, in: Circle())
                    .padding(.top, 24)
                    .accessibilityHidden(true)
                VStack(spacing: 4) {
                    Text("\(model.locationName) done").font(.title2.bold())
                    Text(subtitle).font(.subheadline).foregroundStyle(Color.hsInk2)
                }
                runway
                needsDate
                added
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .background(Color.hsBg)
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 12) {
                Menu {
                    ForEach(locationPaths, id: \.last!.id) { path in
                        Button(path.map(\.name).joined(separator: " › ")) { walkAnother(path.last!.id) }
                    }
                } label: {
                    Text("Walk another spot").frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle(role: .secondary))
                Button("Done", action: finish).buttonStyle(PrimaryButtonStyle())
            }
            .padding(16)
            .background(Color.hsBg)
        }
        .sheet(item: $openLot) { ref in
            NavigationStack { LotDetailView(lotID: ref.id) }
        }
    }

    private var subtitle: String {
        let items = model.walk.itemCount, lots = model.walk.lotCount
        let minutes = max(1, Int((model.walk.elapsed(at: .now) / 60).rounded()))
        return "\(items) \(items == 1 ? "item" : "items") in \(lots) \(lots == 1 ? "lot" : "lots") · about \(minutes) \(minutes == 1 ? "minute" : "minutes")"
    }

    private var locationPaths: [[Location]] { LocationTree.paths(model.inputs?.locations ?? []) }

    @ViewBuilder
    private var runway: some View {
        if let before = model.runwayBefore, let now = model.runwayNow {
            VStack(alignment: .leading, spacing: 8) {
                Text("YOUR RUNWAY NOW").font(.caption.weight(.semibold)).foregroundStyle(Color.hsInk2)
                change("Water", before.water.days, now.water.days)
                change("Food", before.food.days, now.food.days)
            }
            .card()
        }
    }

    private func change(_ label: String, _ before: RunwayRange?, _ now: RunwayRange?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label).foregroundStyle(Color.hsInk2).frame(width: 56, alignment: .leading)
            if let before, let now {
                Text(DaysText(before).number).font(.subheadline).foregroundStyle(Color.hsInk3).numeric()
                Text("→").foregroundStyle(Color.hsInk3)
                Text(DaysText(now).full).font(.title3.bold()).numeric()
                    .foregroundStyle(DaysText.low(now) > DaysText.low(before) ? Color.hsTint : Color.hsInk)
            } else {
                Text("Add your household to see days").font(.subheadline).foregroundStyle(Color.hsInk2)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var needsDate: some View {
        let lots = model.walk.lotsNeedingADate
        if !lots.isEmpty {
            Button {
                router.showLotsNeedingADate()
                finish()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "calendar.badge.exclamationmark").foregroundStyle(Color.hsAmber)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(lots.count == 1 ? "1 item needs a date" : "\(lots.count) items need a date")
                            .font(.headline).foregroundStyle(Color.hsInk)
                        Text("Counted as Good until set").font(.subheadline).foregroundStyle(Color.hsInk2)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(Color.hsInk3)
                }
                .padding(16)
                .background(Color.hsAmberBg, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private var added: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Added").font(.subheadline.weight(.semibold)).foregroundStyle(Color.hsInk2)
                Spacer()
                Text("Tap to edit").font(.subheadline).foregroundStyle(Color.hsInk3)
            }
            .padding(.horizontal, 4)
            VStack(spacing: 0) {
                ForEach(Array(model.walk.groups.enumerated()), id: \.element.productID) { index, group in
                    if index > 0 { Divider().padding(.leading, 16) }
                    Button {
                        if let lot = group.lots.last { openLot = LotRef(id: lot) }
                    } label: {
                        HStack {
                            Text(model.product(group.productID)?.name ?? "Removed product").foregroundStyle(Color.hsInk)
                            Spacer()
                            Text("× \(group.times)").fontWeight(.semibold).foregroundStyle(Color.hsInk).numeric()
                        }
                        .padding(.horizontal, 16).frame(minHeight: 52)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(Color.hsCard, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }
}
