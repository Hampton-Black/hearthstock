import HearthstockCore
import SwiftUI

/// The Dashboard's state: runway and Focus next from Core, recomputed from each snapshot.
@MainActor @Observable
final class DashboardModel: RunwayInputsModel {
    var phase: FeedPhase = .loading
    var inputs: RunwayInputs?
    var today: CalendarDate = .today()
    private(set) var runway: SiteRunway?
    private(set) var focus: [FocusItem] = []
    private let profiles: ShelfLifeProfileTable

    init(profiles: ShelfLifeProfileTable) {
        self.profiles = profiles
    }

    func recompute() {
        guard let inputs else { return }
        let runway = RunwayCalculator.runway(for: inputs, profiles: profiles, on: today)
        let statuses = LotStatusEvaluator.statuses(for: inputs, profiles: profiles, on: today)
        self.runway = runway
        focus = FocusNext.items(runway: runway, statuses: statuses)
    }

    /// The day target the bars and cards measure against: the next one up, or the last once every one is met.
    var targetDays: Double { runway?.nextTarget?.days ?? RunwayCalculator.defaultTargets.max() ?? 14 }

    func products(_ ids: [ProductID]) -> [Product] {
        ids.compactMap { id in inputs?.products.first { $0.id == id } }
    }
}

struct DashboardView: View {
    @Environment(AppSession.self) private var session
    @Environment(AppRouter.self) private var router
    @Environment(Today.self) private var today
    @State private var model: DashboardModel?
    @State private var adding = false
    @State private var fixingProducts: ProductList?

    /// Focus next shows this many rows; the rest are a tap away in Inventory.
    private static let focusLimit = 6

    var body: some View {
        NavigationStack {
            Group {
                if let model {
                    FeedContent(phase: model.phase) {
                        if let runway = model.runway, let inputs = model.inputs {
                            content(model, runway: runway, inputs: inputs)
                        }
                    }
                }
            }
            .background(Color.hsBg)
            .navigationTitle("Runway")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Add item", systemImage: "plus") { adding = true }
                }
            }
            .navigationDestination(for: LotID.self) { LotDetailView(lotID: $0) }
        }
        .task {
            let model = DashboardModel(profiles: session.services.profiles)
            self.model = model
            await model.subscribe(session.services, siteID: session.siteID)
        }
        .onChange(of: today.date, initial: true) { _, day in model?.setToday(day) }
        .sheet(isPresented: $adding) { AddLotSheet() }
        .sheet(item: $fixingProducts) { list in ProductFixList(list: list) }
    }

    private func content(_ model: DashboardModel, runway: SiteRunway, inputs: RunwayInputs) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(subtitle(inputs)).font(.subheadline.weight(.medium)).foregroundStyle(Color.hsInk2)
                    .padding(.horizontal, 4)

                if runway.problems.contains(.noOccupants) {
                    HouseholdPrompt { router.tab = .settings }
                } else if inputs.lots.isEmpty {
                    FirstItemPrompt { adding = true }
                } else if let effective = runway.effective {
                    RunwayHeroCard(runway: runway, effective: effective, targetDays: model.targetDays)
                }

                CategoryCards(runway: runway, targetDays: model.targetDays) { category in
                    router.showInventory(category: category)
                }

                let items = model.focus.filter { $0 != .noOccupants }
                if !items.isEmpty {
                    Text("Focus next").font(.title3.bold()).padding(.horizontal, 4).padding(.top, 4)
                    VStack(spacing: 0) {
                        ForEach(Array(items.prefix(Self.focusLimit).enumerated()), id: \.offset) { index, item in
                            if index > 0 { Divider().padding(.leading, 66) }
                            focusRow(item, model: model)
                        }
                        if items.count > Self.focusLimit {
                            Divider()
                            Button("\(items.count - Self.focusLimit) more in Inventory") {
                                router.showInventory(category: nil)
                            }
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 44)
                        }
                    }
                    .background(Color.hsCard, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
    }

    private func subtitle(_ inputs: RunwayInputs) -> String {
        let count = inputs.occupants.count
        let people = count == 0 ? "no one yet" : count == 1 ? "1 person" : "\(count) people"
        return "\(inputs.site.name) · \(people)"
    }

    @ViewBuilder
    private func focusRow(_ item: FocusItem, model: DashboardModel) -> some View {
        switch item {
        case .noOccupants:
            EmptyView()
        case .reachTarget(let category, let amount, let unit, let targetDays):
            Button { adding = true } label: {
                FocusRow(
                    symbol: "plus", colors: (.hsTint, .hsTintSoft),
                    title: "+\(unit == .kcal ? Amount.kcal(amount.rounded(.up)) : Amount.gallons(amount)) \(category.title.lowercased())",
                    subtitle: "Reaches \(Int(targetDays)) days")
            }
        case .rotate(let status), .useSoon(let status):
            NavigationLink(value: status.id) {
                FocusRow(
                    symbol: status.state?.symbol ?? "clock",
                    colors: status.state?.tileColors ?? (.hsAmber, .hsAmberBg),
                    title: status.product?.name ?? "Unknown product",
                    subtitle: "\(lotSubtitle(status)) · \(QuantityText.format(status.lot, product: status.product))")
            }
        case .missingNutrition(_, let products):
            Button { fixingProducts = ProductList(kind: .calories, products: model.products(products)) } label: {
                FocusRow(
                    symbol: "exclamationmark.circle", colors: (.hsInk2, .hsTrack),
                    title: products.count == 1 ? "1 product missing calories" : "\(products.count) products missing calories",
                    subtitle: "Not counted in food yet")
            }
        case .missingWaterVolume(_, let products):
            Button { fixingProducts = ProductList(kind: .water, products: model.products(products)) } label: {
                FocusRow(
                    symbol: "exclamationmark.circle", colors: (.hsInk2, .hsTrack),
                    title: products.count == 1 ? "1 product missing water volume" : "\(products.count) products missing water volume",
                    subtitle: "Not counted in water yet")
            }
        }
    }

    private func lotSubtitle(_ status: LotStatus) -> String {
        switch status.state {
        case .caution?: "Caution · eat or rotate"
        case .inspect?: "Inspect · check before use"
        case .useSoon?:
            "Use soon · \((status.profile?.dateType ?? .bestBy).label.lowercased()) \(status.lot.printedDate?.medium ?? "")"
        default: status.state?.title ?? ""
        }
    }
}

// MARK: - Cards

/// "You could last about 9–11 days", the limiting callout, the bars and the plan-around line.
private struct RunwayHeroCard: View {
    let runway: SiteRunway
    let effective: RunwayRange
    let targetDays: Double
    @ScaledMetric(relativeTo: .largeTitle) private var heroSize: CGFloat = 64

    var body: some View {
        let days = DaysText(effective)
        let low = DaysText.low(effective)
        let critical = effective.low < 3
        VStack(alignment: .leading, spacing: 10) {
            Text("You could last about").font(.subheadline.weight(.semibold)).foregroundStyle(Color.hsInk2)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(days.number).font(.system(size: heroSize, weight: .bold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(critical ? Color.hsRed : Color.hsInk)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text(days.unit).font(.title2.weight(.semibold)).fontDesign(.rounded).foregroundStyle(Color.hsInk2)
            }
            .accessibilityElement(children: .combine)
            callout(critical: critical)
            RunwayBars(runway: runway, targetDays: targetDays)
            Text(planText(low: low, high: Int(max(0, effective.high).rounded(.down))))
                .font(.footnote).foregroundStyle(Color.hsInk2)
        }
        .card()
    }

    @ViewBuilder
    private func callout(critical: Bool) -> some View {
        let name = runway.limitingCategory?.title ?? "Water"
        let symbol = runway.limitingCategory == .food ? "fork.knife" : "drop.fill"
        if runway.nextTarget == nil {
            Label("At your \(Int(targetDays))-day target", systemImage: "checkmark")
                .font(.subheadline.weight(.semibold)).foregroundStyle(Color.hsGood)
        } else if critical {
            Label("\(name) is below the 3-day minimum", systemImage: symbol)
                .font(.subheadline.weight(.semibold)).foregroundStyle(Color.hsRed)
                .padding(.vertical, 4).padding(.horizontal, 10)
                .background(Color.hsRedBg, in: Capsule())
        } else {
            Label("\(name) is the weakest link", systemImage: symbol)
                .font(.subheadline.weight(.semibold)).foregroundStyle(Color.hsTint)
        }
    }

    private func planText(low: Int, high: Int) -> String {
        let gap = high - low
        let plan = "Plan around \(low) \(low == 1 ? "day" : "days")."
        guard gap > 0 else { return plan }
        if gap == 1 { return "\(plan) The other day depends on stock to eat or rotate first." }
        return "\(plan) The other \(gap) depend on stock to eat or rotate first."
    }
}

/// One bar per category on a shared 0…2× target scale: solid low end, striped high end, target tick.
private struct RunwayBars: View {
    let runway: SiteRunway
    let targetDays: Double
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach([runway.food, runway.water], id: \.category) { category in
                if let days = category.days { row(category.category, days: days) }
            }
        }
    }

    @ViewBuilder
    private func row(_ category: SupplyCategory, days: RunwayRange) -> some View {
        let limiting = category == runway.limitingCategory
        let color: Color = limiting ? (days.low < 3 ? .hsRed : .hsTint) : .hsInk3
        let label = Text(category.title)
            .font(.footnote.weight(limiting ? .bold : .regular))
            .foregroundStyle(limiting ? color : Color.hsInk2)
        let bar = GeometryReader { geometry in
            let scale = max(1, targetDays * 2)
            let width = geometry.size.width
            let low = width * min(1, days.low / scale)
            let high = width * min(1, days.high / scale)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.hsTrack)
                Capsule().fill(color.opacity(0.55)).frame(width: high)
                    .mask(Stripes().frame(width: high))
                Capsule().fill(color).frame(width: low)
                Rectangle().fill(Color.hsInk).frame(width: 2, height: 22)
                    .offset(x: width * min(1, targetDays / scale) - 1)
            }
            .frame(height: 12)
            .frame(maxHeight: .infinity)
        }
        .frame(height: 22)
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) { label; bar }
            } else {
                HStack(spacing: 8) { label.frame(width: 48, alignment: .leading); bar }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(category.title), \(DaysText(days).full), target \(Int(targetDays)) days")
    }
}

/// 45° stripes, 3 pt on and 3 pt off.
private struct Stripes: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        var x = -rect.height
        while x < rect.width + rect.height {
            path.move(to: CGPoint(x: x, y: rect.maxY))
            path.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
            path.addLine(to: CGPoint(x: x + rect.height + 3, y: rect.minY))
            path.addLine(to: CGPoint(x: x + 3, y: rect.maxY))
            path.closeSubpath()
            x += 6
        }
        return path
    }
}

/// Food and water: days, amount on hand, daily need. Tapping one opens Inventory filtered to it.
private struct CategoryCards: View {
    let runway: SiteRunway
    let targetDays: Double
    let open: (SupplyCategory) -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 12)) : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
        layout {
            card(runway.food)
            card(runway.water)
        }
    }

    private func card(_ category: CategoryRunway) -> some View {
        let limiting = category.category == runway.limitingCategory && runway.effective != nil
        let critical = (category.days?.low ?? 0) < 3
        let accent: Color = limiting ? (critical ? .hsRed : .hsTint) : .hsInk2
        return Button { open(category.category) } label: {
            VStack(alignment: .leading, spacing: 2) {
                Label(category.category.title, systemImage: category.category.symbol)
                    .font(.subheadline.weight(.semibold)).foregroundStyle(accent)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    let days = category.days.map(DaysText.init)
                    Text(days?.number ?? "—").font(.title.bold()).fontDesign(.rounded).monospacedDigit()
                        .foregroundStyle(Color.hsInk)
                    Text(days?.unit ?? "days").font(.subheadline.weight(.semibold)).foregroundStyle(Color.hsInk2)
                }
                Text(onHand(category)).font(.footnote).foregroundStyle(Color.hsInk2).numeric()
                if category.dailyNeed > 0 {
                    Text("Need \(need(category)) a day").font(.footnote).foregroundStyle(Color.hsInk2).numeric()
                }
                if category.category == .water, runway.untreatedNonPotableGal > 0 {
                    Text("+ \(Amount.gallons(runway.untreatedNonPotableGal)) not potable")
                        .font(.caption.weight(.semibold)).foregroundStyle(Color.hsInk2)
                        .padding(.vertical, 2).padding(.horizontal, 8)
                        .background(Color.hsTrack, in: Capsule())
                        .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12).padding(.horizontal, 14)
            .background(Color.hsCard, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                if limiting {
                    RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(accent, lineWidth: 2)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows these items in Inventory")
    }

    /// Everything not expired: what's in date plus what needs rotating.
    private func onHand(_ category: CategoryRunway) -> String {
        category.category == .food
            ? "\(Amount.kcal(category.highAmount)) on hand" : "\(Amount.gallons(category.highAmount)) drinkable"
    }

    private func need(_ category: CategoryRunway) -> String {
        category.category == .food
            ? Amount.text(category.dailyNeed, fraction: 0) : Amount.gallons(category.dailyNeed)
    }
}

/// Focus next row: tile, title, subtitle, chevron (hidden at accessibility sizes).
private struct FocusRow: View {
    let symbol: String
    let colors: (foreground: Color, background: Color)
    let title: String
    let subtitle: String
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(spacing: 12) {
            IconTile(symbol: symbol, foreground: colors.foreground, background: colors.background)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline).foregroundStyle(Color.hsInk).multilineTextAlignment(.leading)
                Text(subtitle).font(.subheadline).foregroundStyle(Color.hsInk2).multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
            if !typeSize.isAccessibilitySize {
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Color.hsInk3)
            }
        }
        .padding(.vertical, 10).padding(.horizontal, 16)
        .frame(minHeight: 60)
        .contentShape(Rectangle())
    }
}

private struct HouseholdPrompt: View {
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            IconTile(symbol: "person.2", foreground: .hsTint, background: .hsTintSoft)
            Text("Add your household to compute runway").font(.title2.bold())
            Text("Days depend on who you're feeding. Add each person's daily calories and water, and your supplies turn into days.")
                .font(.body).foregroundStyle(Color.hsInk2)
            Button("Add your household", action: action).buttonStyle(PrimaryButtonStyle())
        }
        .card()
    }
}

private struct FirstItemPrompt: View {
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            IconTile(symbol: "shippingbox", foreground: .hsTint, background: .hsTintSoft)
            Text("Add your first item").font(.title2.bold())
            Text("A bag of rice, a case of water, the old cans at the back of the shelf. Any date works, past or future.")
                .font(.body).foregroundStyle(Color.hsInk2)
            Button("Add item", action: action).buttonStyle(PrimaryButtonStyle())
        }
        .card()
    }
}

// MARK: - Products missing data

struct ProductList: Identifiable {
    enum Kind {
        case calories
        case water
    }

    let kind: Kind
    let products: [Product]
    var id: [ProductID] { products.map(\.id) }
}

/// The products the runway couldn't count, each opening its product form.
private struct ProductFixList: View {
    let list: ProductList
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(list.products) { product in
                NavigationLink(product.name) { ProductForm(editing: product) }
            }
            .hearthList()
            .navigationTitle(list.kind == .calories ? "Missing calories" : "Missing water volume")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
