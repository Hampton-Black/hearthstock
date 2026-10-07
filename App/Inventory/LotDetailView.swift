import HearthstockCore
import SwiftUI

/// Every field of one lot, why it's in its state, and Use, Adjust, Edit, Mark as used up and Delete.
struct LotDetailView: View {
    let lotID: LotID

    @Environment(AppSession.self) private var session
    @Environment(Today.self) private var today
    @Environment(\.dismiss) private var dismiss
    @State private var model: LotModel?
    @State private var sheet: LotSheet?
    @State private var editingLot = false
    @State private var editingProduct: Product?
    @State private var confirmingDelete = false
    @State private var confirmingUsedUp = false
    @State private var writeError: String?

    var body: some View {
        Group {
            if let status = model?.status {
                content(status)
            } else if model?.phase == .live {
                ContentUnavailableView("This item is used up or was deleted", systemImage: "shippingbox")
            } else if case .failed(let message)? = model?.phase {
                FeedFailureView(message: message)
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.hsBg)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let status = model?.status {
                ToolbarItem(placement: .primaryAction) {
                    Menu("Edit") {
                        Button("Edit item", systemImage: "pencil") { editingLot = true }
                        if let product = status.product {
                            Button("Edit product", systemImage: "shippingbox") { editingProduct = product }
                        }
                    }
                }
            }
        }
        .task {
            let model = LotModel(lotID: lotID, profiles: session.services.profiles, today: today.date)
            self.model = model
            await model.subscribe(session.services, siteID: session.siteID)
        }
        .onChange(of: today.date) { _, day in model?.setToday(day) }
        .sheet(item: $sheet) { sheet in UseAdjustSheet(lotID: sheet.lotID, mode: sheet.mode) }
        .sheet(isPresented: $editingLot) {
            if let status = model?.status, let inputs = model?.inputs {
                NavigationStack { LotEditForm(lot: status.lot, product: status.product, inputs: inputs) }
            }
        }
        .sheet(item: $editingProduct) { product in
            NavigationStack { ProductForm(editing: product) }
        }
        .confirmationDialog("Delete this item?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { run { try await session.services.lots.delete(lotID) } }
        } message: {
            Text("For entry mistakes: it's removed completely. To record that you used it, mark it used up instead.")
        }
        .confirmationDialog("Mark as used up?", isPresented: $confirmingUsedUp, titleVisibility: .visible) {
            Button("Mark as used up") { run { try await session.services.lots.archive(lotID) } }
        } message: {
            Text("It leaves your inventory and runway but stays in your history.")
        }
        .errorAlert($writeError)
    }

    private func content(_ status: LotStatus) -> some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text([LotText.path(status), status.product?.category.title].compactMap { $0 }.filter { !$0.isEmpty }
                        .joined(separator: " · "))
                        .font(.subheadline).foregroundStyle(Color.hsInk2)
                    Text(status.product?.name ?? "Unknown product").font(.largeTitle.bold()).foregroundStyle(Color.hsInk)
                }
                .listRowBackground(Color.clear)
            }

            Section {
                VStack(alignment: .leading, spacing: 12) {
                    if let state = status.state { StateBadge(state: state) }
                    Text(LotText.why(status, today: today.date)).font(.body)
                    if let evaluation = status.evaluation, evaluation.timeline != nil {
                        LotTimeline(lot: status.lot, evaluation: evaluation, today: today.date)
                    }
                }
                .padding(.vertical, 6)
            }

            if let profile = status.profile, let evaluation = status.evaluation {
                Section {
                    LabeledContent("Printed date") {
                        Text(status.lot.printedDate.map { "\(profile.dateType.label) \($0.medium)" } ?? "None")
                    }
                    LabeledContent {
                        Text(profile.name).multilineTextAlignment(.trailing)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Shelf-life profile")
                            Text(ProfileText.summary(profile)).font(.caption).foregroundStyle(Color.hsInk2)
                        }
                    }
                    LabeledContent {
                        Text(status.climate.title).multilineTextAlignment(.trailing)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Storage climate")
                            Text(climateNote(status)).font(.caption).foregroundStyle(Color.hsInk2)
                        }
                    }
                    LabeledContent("Humidity", value: status.humidity.title)
                    LabeledContent("Packaging", value: status.lot.packaging.title)
                    LabeledContent("Usable by") {
                        Text(evaluation.usableBy?.medium ?? "No limit").fontWeight(.semibold)
                    }
                    LabeledContent("Runway", value: LotText.runway(RunwayEffect(status)))
                } header: {
                    Text("Why it's \(evaluation.state.title)")
                } footer: {
                    if let timeline = evaluation.timeline, evaluation.state != .expired {
                        Text("Inspect starts \(timeline.inspectFrom.medium), in the last 20% of the window. Bulging, rusted or leaking cans go regardless of date.")
                    }
                }
            } else {
                Section { Text(LotText.problem(status)).foregroundStyle(Color.hsAmber) }
            }

            Section("Lot") {
                VStack(spacing: 12) {
                    LabeledContent("Quantity") {
                        Text(quantityText(status)).fontWeight(.semibold).numeric()
                    }
                    HStack(spacing: 12) {
                        Button("Use some") { sheet = LotSheet(lotID: lotID, mode: .use) }
                            .buttonStyle(PrimaryButtonStyle(role: .secondary))
                        Button("Adjust") { sheet = LotSheet(lotID: lotID, mode: .adjust) }
                            .buttonStyle(PrimaryButtonStyle(role: .secondary))
                    }
                    .buttonStyle(.borderless)
                }
                LabeledContent("Location", value: LotText.path(status))
                LabeledContent("Acquired", value: status.lot.acquiredDate.medium)
                LabeledContent("Opened", value: status.lot.opened ? "Yes" : "No")
                if let notes = status.lot.notes {
                    LabeledContent("Notes", value: notes)
                }
                if let override = status.lot.climateOverride {
                    LabeledContent("Spot climate", value: override.title)
                }
            }

            Section {
                Button("Mark as used up", systemImage: "archivebox") { confirmingUsedUp = true }
                Button("Delete lot", systemImage: "trash", role: .destructive) { confirmingDelete = true }
            } footer: {
                Text("Used up keeps the lot in your history at zero. Delete is for entry mistakes and removes it completely.")
            }
        }
        .hearthList()
    }

    private func quantityText(_ status: LotStatus) -> String {
        var text = QuantityText.format(status.lot, product: status.product)
        if case .counts(_, let amount, let unit, _) = RunwayEffect(status) {
            text += " · " + (unit == .kcal ? Amount.kcal(amount) : Amount.gallons(amount))
        }
        return text
    }

    private func climateNote(_ status: LotStatus) -> String {
        if status.lot.climateOverride != nil { return "Set on this item" }
        let from = status.locationChain.first { $0.climateClass != nil }?.name
        let multiplier = status.windowMultiplierOverride ?? status.climate.defaultWindowMultiplier
        var parts: [String] = []
        if let from { parts.append("From \(from)") } else { parts.append("No location sets one") }
        if let multiplier { parts.append("window ×\(Amount.text(multiplier))") }
        if status.climate.defaultWindowMultiplier == nil { parts.append("needs power") }
        return parts.joined(separator: " · ")
    }

    private func run(_ write: @escaping () async throws -> Void) {
        Task {
            do {
                try await write()
                dismiss()
            } catch {
                writeError = ErrorText.describe(error)
            }
        }
    }
}

/// A bar from the start of the lot's window to its usable-by date, split into Good, Use soon, Caution and Inspect,
/// with a Today marker (design.md §6, LotTimeline).
struct LotTimeline: View {
    let lot: Lot
    let evaluation: ShelfLifeEvaluation
    let today: CalendarDate

    /// Where `date` falls between the start of the window and its usable-by date, clamped to 0...1.
    private func fraction(_ date: CalendarDate) -> CGFloat {
        guard let timeline = evaluation.timeline, let usableBy = evaluation.usableBy else { return 0 }
        let start = min(lot.acquiredDate, timeline.goodThrough)
        let span = max(1, start.days(until: usableBy))
        return CGFloat(min(max(0, start.days(until: date)), span)) / CGFloat(span)
    }

    var body: some View {
        if let timeline = evaluation.timeline, let usableBy = evaluation.usableBy {
            VStack(spacing: 6) {
                GeometryReader { geometry in
                    let width = geometry.size.width
                    let useSoon = timeline.useSoonFrom.map(fraction) ?? fraction(timeline.goodThrough)
                    let good = fraction(timeline.goodThrough)
                    let inspect = fraction(timeline.inspectFrom)
                    ZStack(alignment: .leading) {
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.hsTrack)
                            Rectangle().fill(Color.hsGood).frame(width: width * useSoon)
                            Rectangle().fill(Color.hsAmberLine.opacity(0.5))
                                .frame(width: width * max(0, good - useSoon)).offset(x: width * useSoon)
                            if timeline.hasCaution {
                                Rectangle().fill(Color.hsAmberLine)
                                    .frame(width: width * max(0, inspect - good)).offset(x: width * good)
                            }
                            Rectangle().strokeBorder(Color.hsAmberLine, lineWidth: 1.5)
                                .frame(width: width * max(0, 1 - inspect)).offset(x: width * inspect)
                        }
                        .frame(height: 12)
                        .clipShape(Capsule())
                        Rectangle().fill(Color.hsInk).frame(width: 3, height: 20)
                            .offset(x: min(width - 3, width * fraction(today)))
                    }
                    .frame(maxHeight: .infinity)
                }
                .frame(height: 20)
                HStack {
                    Text("\(timeline.fromPrintedDate ? "Bought" : "Stored")\n\(lot.acquiredDate.monthYear)")
                    Spacer()
                    Text("Today").fontWeight(.semibold)
                    Spacer()
                    Text("Usable by\n\(usableBy.monthYear)").multilineTextAlignment(.trailing)
                }
                .font(.caption)
                .foregroundStyle(Color.hsInk3)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Usable by \(usableBy.medium)")
        }
    }
}
