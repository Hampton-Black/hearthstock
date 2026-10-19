import HearthstockCore
import SwiftUI

/// Which walk is running, so "Walk another spot" can start a fresh one.
struct WalkStart: Identifiable {
    let id = UUID()
    let locationID: LocationID
}

/// Pantry walk (Walk-Mode): the camera stays open with the location locked; each scan raises a confirm card, each
/// Add saves at once, and Done shows the summary.
struct PantryWalkView: View {
    let start: WalkStart
    let walkAnother: (LocationID) -> Void
    let finish: () -> Void

    @Environment(AppSession.self) private var session
    @Environment(Today.self) private var today
    @State private var model: PantryWalkModel?
    @State private var showingSummary = false

    var body: some View {
        Group {
            if let model {
                if showingSummary {
                    WalkSummaryView(model: model, walkAnother: walkAnother, finish: finish)
                } else {
                    camera(model)
                }
            } else {
                Color.hsCameraBg.ignoresSafeArea()
            }
        }
        .task {
            let model = PantryWalkModel(
                services: session.services, siteID: session.siteID, locationID: start.locationID, today: today.date)
            self.model = model
            await model.subscribe(session.services, siteID: session.siteID)
        }
        .onChange(of: today.date) { _, day in model?.setToday(day) }
    }

    @ViewBuilder
    private func camera(_ model: PantryWalkModel) -> some View {
        @Bindable var model = model
        CameraScreen(
            scanner: model.scanner,
            showsReticle: model.card == nil && model.duplicate == nil && model.lookingUp == nil,
            leading: {
                Label(model.locationName, systemImage: "lock.fill")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14).frame(minHeight: 40)
                    .background(Color.hsCameraControl, in: Capsule())
                    .accessibilityLabel("Walking \(model.locationName)")
            },
            center: { EmptyView() },
            trailing: {
                Button("Done") {
                    if model.walk.itemCount == 0 { finish() } else { showingSummary = true }
                }
                .buttonStyle(CameraPillStyle(prominent: true))
            },
            bottom: {
                VStack(spacing: 12) {
                    if model.walk.itemCount > 0 {
                        Label("\(model.walk.itemCount) added this walk", systemImage: "checkmark")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14).frame(minHeight: 36)
                            .foregroundStyle(Color.hsOnTint)
                            .background(Color.hsTint, in: Capsule())
                            .environment(\.colorScheme, .light)
                    }
                    if let lastAdded = model.lastAdded, model.card == nil, model.duplicate == nil {
                        HStack {
                            Label {
                                Text("Added ").foregroundStyle(Color.hsCameraInk2) + Text(lastAdded)
                            } icon: {
                                Image(systemName: "checkmark").foregroundStyle(Color.hsCameraAccent)
                            }
                            .font(.subheadline)
                            Spacer()
                            Button("Undo") { Task { await model.undo() } }
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.hsCameraAccent)
                        }
                        .padding(.horizontal, 16).frame(minHeight: 48)
                        .background(Color.hsCameraControl, in: RoundedRectangle(cornerRadius: 14))
                    }
                    if let code = model.lookingUp {
                        HStack(spacing: 10) {
                            ProgressView().tint(Color.hsCameraInk)
                            Text("Looking up \(code.rawValue)…").font(.subheadline.monospacedDigit())
                        }
                        .padding(.horizontal, 16).frame(minHeight: 48)
                        .background(Color.hsCameraControl, in: Capsule())
                    }
                    if model.card != nil {
                        WalkConfirmCard(model: model)
                    } else if let duplicate = model.duplicate {
                        WalkDuplicateCard(duplicate: duplicate, model: model)
                    }
                }
            })
        .sensoryFeedback(.success, trigger: model.saves)
        .errorAlert($model.writeError)
    }
}

// MARK: - Confirm card

/// WalkConfirmCard (design §6): a light card over the camera with the item, quantity, printed date chip, and a 1:2
/// Skip / Add row.
struct WalkConfirmCard: View {
    let model: PantryWalkModel
    @State private var choosingDate = false
    @Environment(\.dynamicTypeSize) private var typeSize

    /// Side by side, or stacked at accessibility text sizes (design §7).
    private var row: AnyLayout {
        typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(spacing: 12))
    }

    var body: some View {
        if let card = model.card {
            content(card)
                .environment(\.colorScheme, .light)
                .sheet(isPresented: $choosingDate) { dateSheet(card) }
                .task(id: card.id) {
                    if card.opensDateSheet { choosingDate = true }
                }
        }
    }

    @ViewBuilder
    private func content(_ card: PantryWalkModel.Card) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(header(card)).font(.caption.weight(.semibold)).foregroundStyle(Color.hsInk2)
            if card.asksForBasics {
                newProductFields(card)
            } else {
                Text(card.name).font(.title3.bold()).foregroundStyle(Color.hsInk)
            }
            row {
                quantity(card)
                if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
                Button { choosingDate = true } label: {
                    Text(dateChip(card)).font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12).frame(minHeight: 44)
                        .background(Color.hsTrack, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(card.printed == .unset && needsDate(card) ? Color.hsAmber : Color.hsInk)
                }
                .disabled(!needsDate(card))
            }
            if typeSize.isAccessibilitySize {
                VStack(spacing: 12) {
                    addButton(card)
                    Button("Skip") { model.skip() }.buttonStyle(PrimaryButtonStyle(role: .secondary))
                }
            } else {
                // Skip and Add at 1:2 (design §6).
                Grid(horizontalSpacing: 12) {
                    GridRow {
                        Button("Skip") { model.skip() }
                            .buttonStyle(PrimaryButtonStyle(role: .secondary))
                        addButton(card).gridCellColumns(2)
                    }
                }
            }
        }
        .padding(16)
        .foregroundStyle(Color.hsInk)
        .background(Color.hsCard, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func addButton(_ card: PantryWalkModel.Card) -> some View {
        Button("Add to \(model.locationName)") { Task { await model.add() } }
            .buttonStyle(PrimaryButtonStyle())
            .lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
            .minimumScaleFactor(0.8)
            .disabled(!canAdd(card))
            .opacity(canAdd(card) ? 1 : 0.5)
    }

    private func header(_ card: PantryWalkModel.Card) -> String {
        let category = card.category.title.uppercased()
        switch card.subject {
        case .known: return "BARCODE MATCH · \(category)"
        case .new(_, found: true, _): return "FROM OPEN FOOD FACTS · \(category)"
        case .new(_, found: false, let reason?): return reason == .switchedOff ? "NEW BARCODE" : "COULDN'T LOOK IT UP"
        case .new: return "NOT FOUND · ADD WHAT YOU KNOW"
        }
    }

    @ViewBuilder
    private func newProductFields(_ card: PantryWalkModel.Card) -> some View {
        if case .new(var draft, let found, let reason) = card.subject {
            VStack(spacing: 8) {
                TextField("Name", text: Binding(get: { draft.name }, set: { name in
                    draft.name = name
                    model.card?.subject = .new(draft, found: found, reason: reason)
                }))
                .font(.title3.bold())
                HStack {
                    Picker("Category", selection: Binding(get: { draft.category }, set: { category in
                        let oldDefault = ProductDraft.defaultProfileKey(for: draft.category)
                        draft.category = category
                        if draft.shelfLifeProfileKey == oldDefault {
                            draft.shelfLifeProfileKey = ProductDraft.defaultProfileKey(for: category)
                        }
                        if category != .food { draft.kcalPerBaseUnit = nil }
                        model.card?.subject = .new(draft, found: found, reason: reason)
                    })) {
                        ForEach(SupplyCategory.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    Spacer()
                    if draft.category == .food {
                        TextField("kcal per item", value: Binding(get: { draft.kcalPerBaseUnit }, set: { kcal in
                            draft.kcalPerBaseUnit = kcal
                            model.card?.subject = .new(draft, found: found, reason: reason)
                        }), format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 140)
                    }
                }
                if let reason, reason != .switchedOff {
                    Label(LookupText.unavailable(reason), systemImage: reason == .offline ? "wifi.slash" : "exclamationmark.circle")
                        .font(.caption).foregroundStyle(Color.hsInk2)
                }
            }
        }
    }

    @ViewBuilder
    private func quantity(_ card: PantryWalkModel.Card) -> some View {
        if card.unitKind == .count {
            HStack(spacing: 10) {
                stepButton("minus", label: "One fewer") {
                    if let amount = card.amount, amount > 1 { model.card?.amount = amount - 1 }
                }
                Text(Amount.text(card.amount ?? 1)).font(.title2.bold()).numeric().frame(minWidth: 32)
                stepButton("plus", label: "One more") { model.card?.amount = (card.amount ?? 0) + 1 }
                Text((card.amount ?? 1) == 1 ? "item" : "items").foregroundStyle(Color.hsInk2)
            }
            .fixedSize()
        } else {
            HStack(spacing: 8) {
                TextField("Amount", value: Binding(get: { card.amount }, set: { model.card?.amount = $0 }), format: .number)
                    .keyboardType(.decimalPad)
                    .font(.title3.weight(.semibold)).numeric()
                    .frame(maxWidth: 90)
                    .padding(.vertical, 8).padding(.horizontal, 10)
                    .background(Color.hsTrack, in: RoundedRectangle(cornerRadius: 10))
                Text(card.unitKind.baseUnit.symbol).foregroundStyle(Color.hsInk2)
            }
        }
    }

    private func stepButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.body.weight(.semibold))
                .frame(width: 44, height: 44)
                .background(Color.hsTrack, in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(Color.hsInk)
        }
        .accessibilityLabel(label)
    }

    private func needsDate(_ card: PantryWalkModel.Card) -> Bool {
        model.profile(for: card)?.dateType != ShelfLifeDateType.none
    }

    private func dateChip(_ card: PantryWalkModel.Card) -> String {
        guard needsDate(card) else { return "Filled today" }
        switch card.printed {
        case .unset: return "Add date"
        case .noPrintedDate: return "No printed date"
        case .day(let date): return "\((model.profile(for: card)?.dateType ?? .bestBy).label) \(date.monthYear)"
        }
    }

    private func canAdd(_ card: PantryWalkModel.Card) -> Bool {
        guard let amount = card.amount, amount > 0 else { return false }
        return !card.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func dateSheet(_ card: PantryWalkModel.Card) -> some View {
        PrintedDateSheet(
            printed: Binding(get: { model.card?.printed ?? .unset }, set: { model.card?.printed = $0 }),
            estimateMonths: Binding(get: { model.card?.estimateMonths }, set: { model.card?.estimateMonths = $0 }),
            profile: model.profile(for: card), today: model.today,
            estimate: { months in estimate(card, months: months) },
            previewState: { date in stateIfPrinted(card, date) })
    }

    private func stateIfPrinted(_ card: PantryWalkModel.Card, _ date: CalendarDate) -> LotState? {
        evaluate(card, printed: date, noPrintedDate: false, months: nil)?.state
    }

    /// The estimated usable-by date for this card's lot marked "no printed date".
    private func estimate(_ card: PantryWalkModel.Card, months: Int?) -> CalendarDate? {
        evaluate(card, printed: nil, noPrintedDate: true, months: months)?.evaluation?.usableBy
    }

    /// This card's lot as it would be saved, evaluated today.
    private func evaluate(
        _ card: PantryWalkModel.Card, printed: CalendarDate?, noPrintedDate: Bool, months: Int?
    ) -> LotStatus? {
        guard let inputs = model.inputs else { return nil }
        let product: Product
        switch card.subject {
        case .known(let existing): product = existing
        case .new(let draft, _, _):
            guard let built = try? draft.product() else { return nil }
            product = built
        }
        let lot = Lot(
            productID: product.id, quantity: card.amount ?? 1, acquiredDate: model.today, printedDate: printed,
            noPrintedDate: noPrintedDate, locationID: model.walk.locationID)
        var products = inputs.products.filter { $0.id != product.id }
        products.append(product)
        return LotStatusEvaluator.statuses(
            for: inputs.site, lots: [lot], products: products, locations: inputs.locations, kits: inputs.kits,
            lotShelfLifeOverrides: months.map { [lot.id: ShelfLifeOverride(rotationMonths: $0)] } ?? [:],
            profiles: model.services.profiles, on: model.today
        ).first
    }
}

// MARK: - Scanned again

/// Walk-Duplicate: the code was just added. One more, a double scan, or a new lot with its own date.
struct WalkDuplicateCard: View {
    let duplicate: PantryWalkModel.Duplicate
    let model: PantryWalkModel
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                IconTile(symbol: "arrow.triangle.2.circlepath")
                VStack(alignment: .leading, spacing: 2) {
                    Text("SCANNED AGAIN").font(.caption.weight(.semibold)).foregroundStyle(Color.hsInk2)
                    Text(duplicate.product.name).font(.title3.bold()).foregroundStyle(Color.hsInk)
                    Text("You added one a moment ago.").font(.subheadline).foregroundStyle(Color.hsInk2)
                }
            }
            Button("Add another · makes \(QuantityText.format(duplicate.total, duplicate.product.baseUnit))") {
                Task { await model.addAnother() }
            }
            .buttonStyle(PrimaryButtonStyle())
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: 12)) : AnyLayout(HStackLayout(spacing: 12))
            layout {
                Button("Oops, double scan") { model.doubleScan() }
                    .buttonStyle(PrimaryButtonStyle(role: .secondary))
                Button("Different date") { model.differentDate() }
                    .buttonStyle(PrimaryButtonStyle(role: .secondary))
            }
        }
        .padding(16)
        .foregroundStyle(Color.hsInk)
        .background(Color.hsCard, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .environment(\.colorScheme, .light)
    }
}
