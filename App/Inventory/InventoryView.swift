import HearthstockCore
import SwiftUI

/// Inventory's state: the subscription plus one call to `Inventory.sections`.
@MainActor @Observable
final class InventoryModel: RunwayInputsModel {
    var phase: FeedPhase = .loading
    var inputs: RunwayInputs?
    var today: CalendarDate = .today()
    var query = InventoryQuery() { didSet { recompute() } }
    private(set) var sections: [InventorySection] = []
    private(set) var hasLots = false
    private let profiles: ShelfLifeProfileTable

    init(profiles: ShelfLifeProfileTable) {
        self.profiles = profiles
    }

    func recompute() {
        guard let inputs else { return }
        let statuses = LotStatusEvaluator.statuses(for: inputs, profiles: profiles, on: today)
        hasLots = !statuses.isEmpty
        sections = Inventory.sections(statuses, locations: inputs.locations, query: query)
    }
}

struct InventoryView: View {
    @Environment(AppSession.self) private var session
    @Environment(AppRouter.self) private var router
    @Environment(Today.self) private var today
    @State private var model: InventoryModel?
    @State private var sheet: LotSheet?

    var body: some View {
        NavigationStack {
            Group {
                if let model {
                    FeedContent(phase: model.phase) { content(model) }
                }
            }
            .background(Color.hsBg)
            .navigationTitle("Inventory")
            .addItemButton()
            .navigationDestination(for: LotID.self) { LotDetailView(lotID: $0) }
        }
        .task {
            let model = InventoryModel(profiles: session.services.profiles)
            model.query.category = router.inventoryCategory
            self.model = model
            await model.subscribe(session.services, siteID: session.siteID)
        }
        .onChange(of: today.date, initial: true) { _, day in model?.setToday(day) }
        .onChange(of: router.inventoryDrillIn) { model?.query.category = router.inventoryCategory }
        .sheet(item: $sheet) { sheet in UseAdjustSheet(lotID: sheet.lotID, mode: sheet.mode) }
    }

    @ViewBuilder
    private func content(_ model: InventoryModel) -> some View {
        @Bindable var model = model
        List {
            Section {
                Picker("Group", selection: $model.query.grouping) {
                    Text("By location").tag(InventoryGrouping.location)
                    Text("By category").tag(InventoryGrouping.category)
                }
                .pickerStyle(.segmented)
                filterChips(model)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))

            if model.sections.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label(model.hasLots ? "No matches" : "No items yet", systemImage: model.hasLots ? "magnifyingglass" : "shippingbox")
                    } description: {
                        Text(model.hasLots ? "Try a different search or clear the filters." : "Tap + to add your first item.")
                    }
                }
                .listRowBackground(Color.clear)
            }

            ForEach(model.sections) { section in
                Section {
                    ForEach(section.lots) { status in
                        NavigationLink(value: status.id) {
                            LotRow(status: status, showPath: model.query.grouping == .category)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button("Adjust", systemImage: "slider.horizontal.3") {
                                sheet = LotSheet(lotID: status.id, mode: .adjust)
                            }
                            .tint(.hsInk3)
                            Button("Use", systemImage: "minus.circle") {
                                sheet = LotSheet(lotID: status.id, mode: .use)
                            }
                            .tint(.hsTint)
                        }
                    }
                } header: {
                    HStack {
                        sectionTitle(section)
                        Spacer()
                        Text("\(section.lots.count) \(section.lots.count == 1 ? "lot" : "lots")").numeric()
                    }
                }
            }
        }
        .hearthList()
        .searchable(text: $model.query.search, prompt: "Search names and notes")
    }

    @ViewBuilder
    private func filterChips(_ model: InventoryModel) -> some View {
        HStack(spacing: 8) {
            if let category = model.query.category {
                Button {
                    model.query.category = nil
                    router.inventoryCategory = nil
                } label: {
                    Label {
                        HStack(spacing: 6) {
                            Text(category.title)
                            Image(systemName: "xmark").font(.caption.weight(.bold))
                        }
                    } icon: {
                        Image(systemName: category.symbol)
                    }
                }
                .buttonStyle(ChipStyle(selected: true))
                .accessibilityLabel("\(category.title) filter, clear")
            }
            Button {
                model.query.expiringSoon.toggle()
            } label: {
                Label("Expiring soon", systemImage: "clock")
            }
            .buttonStyle(ChipStyle(selected: model.query.expiringSoon))
            .accessibilityAddTraits(model.query.expiringSoon ? .isSelected : [])
            Spacer()
        }
    }

    private func sectionTitle(_ section: InventorySection) -> some View {
        Group {
            switch section.kind {
            case .location(let path):
                HStack(spacing: 4) {
                    Text(path.map(\.name).joined(separator: " › "))
                    if section.isKit { Image(systemName: "backpack").accessibilityLabel("Kit") }
                }
            case .category(let category): Label(category.title, systemImage: category.symbol)
            case .unplaced: Text("Needs attention")
            }
        }
    }
}

/// A Use or Adjust sheet to present for a lot.
struct LotSheet: Identifiable {
    let lotID: LotID
    let mode: UseAdjustSheet.Mode
    var id: String { "\(lotID)-\(mode)" }
}

/// One Inventory row: name, quantity and date, location path when grouped by category, flags, state badge.
struct LotRow: View {
    let status: LotStatus
    var showPath = false
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
        layout {
            VStack(alignment: .leading, spacing: 2) {
                Text(status.product?.name ?? "Unknown product").font(.headline).foregroundStyle(Color.hsInk)
                Text(LotText.detailLine(status)).font(.subheadline).foregroundStyle(Color.hsInk2).numeric()
                if showPath, !status.locationChain.isEmpty {
                    Label(LotText.path(status), systemImage: "mappin.and.ellipse")
                        .font(.footnote).foregroundStyle(Color.hsInk2)
                }
                let notPotable = status.product?.category == .water && status.product?.potableWaterGalPerBaseUnit == nil
                let flags = status.evaluation?.flags ?? []
                if !flags.isEmpty || notPotable {
                    LotFlagIcons(flags: flags, notPotable: notPotable)
                }
            }
            if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
            if let state = status.state {
                StateBadge(state: state)
            } else {
                Label("Can't evaluate", systemImage: "exclamationmark.triangle")
                    .font(.footnote).foregroundStyle(Color.hsAmber)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A filter chip: `tint` fill when on, card when off.
struct ChipStyle: ButtonStyle {
    var selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .foregroundStyle(selected ? Color.hsOnTint : Color.hsInk)
            .background(selected ? Color.hsTint : Color.hsCard, in: Capsule())
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}
