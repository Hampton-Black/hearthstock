import HearthstockCore
import SwiftUI

/// The Add sheet: one lot (and its product, if new) in one save. Opened from the "+" toolbar button.
struct AddLotSheet: View {
    @Environment(AppSession.self) private var session
    @Environment(Today.self) private var today
    @Environment(\.dismiss) private var dismiss
    @State private var model: AddLotModel?
    @State private var writeError: String?
    @State private var choosingProduct = false
    @State private var choosingDate = false
    @State private var showingSaved = false
    /// The last "Save + add another" lot, shown in a banner above the fresh form.
    @State private var lastQuickSave: LotID?

    var body: some View {
        NavigationStack {
            Group {
                if let model {
                    FeedContent(phase: model.phase) {
                        if showingSaved, let status = model.savedStatus {
                            SavedLotView(status: status, today: today.date) {
                                showingSaved = false
                            } done: {
                                dismiss()
                            }
                        } else if showingSaved {
                            ProgressView()
                        } else {
                            form(model)
                        }
                    }
                }
            }
            .background(Color.hsBg)
            .navigationTitle(showingSaved ? "" : "Add item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !showingSaved {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                }
            }
        }
        .task {
            let model = AddLotModel(services: session.services, siteID: session.siteID, today: today.date)
            self.model = model
            await model.subscribe(session.services, siteID: session.siteID)
        }
        .onChange(of: today.date) { _, day in model?.setToday(day) }
        .errorAlert($writeError)
        .sensoryFeedback(.success, trigger: model?.savedLotID)
        .interactiveDismissDisabled(model?.product != nil && !showingSaved)
    }

    @ViewBuilder
    private func form(_ model: AddLotModel) -> some View {
        @Bindable var model = model
        Form {
            if let lastQuickSave, lastQuickSave == model.savedLotID, let status = model.savedStatus {
                Section {
                    HStack {
                        Label("Saved \(status.product?.name ?? "item")", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(Color.hsGood)
                        Spacer()
                        if let state = status.state { StateBadge(state: state) }
                    }
                }
            }

            Section("Product") {
                Button {
                    choosingProduct = true
                } label: {
                    if let product = model.product {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(product.name).font(.headline).foregroundStyle(Color.hsInk)
                                Text(productSubtitle(product, model: model))
                                    .font(.subheadline).foregroundStyle(Color.hsInk2)
                            }
                            Spacer()
                            Text("Change").foregroundStyle(Color.hsTint)
                        }
                    } else {
                        Label("Choose product", systemImage: "magnifyingglass")
                    }
                }
            }

            if let product = model.product {
                quantitySection(model, kind: product.unitKind)
            }

            Section {
                Button {
                    choosingDate = true
                } label: {
                    LabeledContent("Printed date") {
                        Text(printedText(model)).foregroundStyle(Color.hsInk2)
                    }
                }
                .foregroundStyle(Color.hsInk)
                DatePicker(
                    "Acquired",
                    selection: Binding(get: { model.acquired.pickerDate }, set: { model.acquired = CalendarDate(pickerDate: $0) }),
                    displayedComponents: .date)
            } header: {
                Text("Dates")
            } footer: {
                if let preview = model.preview, let state = preview.state {
                    HStack(spacing: 6) {
                        Text("Today this is")
                        StateBadge(state: state)
                    }
                } else {
                    Text("Any date works, past or future.")
                }
            }

            Section {
                if model.locationPaths.isEmpty {
                    Text("Add a location in Settings first.").foregroundStyle(Color.hsInk2)
                } else {
                    Picker(selection: $model.locationID) {
                        ForEach(model.locationPaths, id: \.last!.id) { path in
                            Text(path.map(\.name).joined(separator: " › ")).tag(Optional(path.last!.id))
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text("Location")
                            if model.locationID != nil, model.locationID == model.lastUsedLocationID {
                                Text("Last used")
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Color.hsTrack, in: Capsule())
                                    .foregroundStyle(Color.hsInk2)
                            }
                        }
                    }
                }
                Picker("Packaging", selection: $model.packaging) {
                    ForEach(Packaging.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Toggle("Opened", isOn: $model.opened)
                TextField("Notes", text: $model.notes, axis: .vertical)
            } header: {
                Text("Storage")
            } footer: {
                Text("Mylar with an O₂ absorber and sealed buckets switch dry goods to a much longer shelf life.")
            }

            Section {
                HStack(spacing: 12) {
                    Button("Save + add another") { save(model, addAnother: true) }
                        .buttonStyle(PrimaryButtonStyle(role: .secondary))
                    Button("Save") { save(model, addAnother: false) }
                        .buttonStyle(PrimaryButtonStyle())
                }
                .disabled(!model.canSave)
                .opacity(model.canSave ? 1 : 0.5)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            } footer: {
                Text("Add another keeps the location and acquired date.").frame(maxWidth: .infinity)
            }
        }
        .hearthList()
        .sheet(isPresented: $choosingProduct) {
            NavigationStack {
                ProductPicker { choice in
                    switch choice {
                    case .existing(let product): model.product = .existing(product)
                    case .new(let draft): model.product = .new(draft)
                    }
                }
            }
        }
        .sheet(isPresented: $choosingDate) {
            PrintedDateSheet(
                printed: $model.printed, dateType: model.profile?.dateType ?? .bestBy, today: today.date)
        }
    }

    private func quantitySection(_ model: AddLotModel, kind: UnitKind) -> some View {
        @Bindable var model = model
        let units = QuantityUnit.entryUnits(for: kind)
        return Section {
            HStack(spacing: 12) {
                TextField("Amount", value: $model.amount, format: .number)
                    .keyboardType(.decimalPad)
                    .font(.title3.weight(.semibold)).numeric()
                    .frame(maxWidth: 110)
                    .padding(.vertical, 6).padding(.horizontal, 10)
                    .background(Color.hsTrack, in: RoundedRectangle(cornerRadius: 10))
                if units.count > 1 {
                    Picker("Unit", selection: $model.unit) {
                        ForEach(units, id: \.self) { Text($0.symbol).tag($0) }
                    }
                    .pickerStyle(.segmented)
                } else {
                    Text(units[0].symbol).foregroundStyle(Color.hsInk2)
                    Spacer()
                }
            }
            Toggle("× packs", isOn: $model.usePacks.animation())
            if model.usePacks {
                Stepper(value: $model.packs, in: 1...999) {
                    LabeledContent("Packs") { Text("\(model.packs)").numeric().foregroundStyle(Color.hsInk) }
                }
            }
        } header: {
            Text("Quantity")
        } footer: {
            if let text = model.storedAmountText {
                Text("**\(text)** will be saved").numeric()
            } else if model.amount != nil && model.baseAmount == nil {
                Text("Enter an amount greater than zero.").foregroundStyle(Color.hsRed)
            }
        }
    }

    private func productSubtitle(_ product: AddLotModel.ProductChoice, model: AddLotModel) -> String {
        var parts = [product.category.title, product.unitKind.title.lowercased()]
        if let profile = model.profile { parts.append(profile.name) }
        if case .new = product { parts.insert("New", at: 0) }
        return parts.joined(separator: " · ")
    }

    private func printedText(_ model: AddLotModel) -> String {
        switch model.printed {
        case .unset: "Not set"
        case .none: "No expiry"
        case .day(let date): "\((model.profile?.dateType ?? .bestBy).label) \(date.medium)"
        }
    }

    private func save(_ model: AddLotModel, addAnother: Bool) {
        Task {
            do {
                try await model.save()
                if addAnother {
                    lastQuickSave = model.savedLotID
                } else {
                    showingSaved = true
                }
            } catch {
                writeError = ErrorText.describe(error)
            }
        }
    }
}

/// The confirmation after Save: the new lot's state, why, and what it adds to runway.
struct SavedLotView: View {
    let status: LotStatus
    let today: CalendarDate
    let addAnother: () -> Void
    let done: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Color.hsOnTint)
                .frame(width: 64, height: 64)
                .background(Color.hsTint, in: Circle())
                .padding(.top, 24)
                .accessibilityHidden(true)
            Text("Saved to \(status.locationChain.first?.name ?? "inventory")")
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(status.product?.name ?? "Item").font(.title3.bold())
                    Spacer()
                    if let state = status.state { StateBadge(state: state) }
                }
                Text(LotText.detailLine(status)).font(.subheadline).foregroundStyle(Color.hsInk2)
                Text(LotText.why(status, today: today)).font(.subheadline)
                Divider()
                LabeledContent("Runway") {
                    Text(LotText.runway(RunwayEffect(status))).font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.hsInk).numeric()
                }
                .font(.subheadline)
            }
            .card()
            Spacer()
            HStack(spacing: 12) {
                Button("Add another", action: addAnother).buttonStyle(PrimaryButtonStyle(role: .secondary))
                Button("Done", action: done).buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }
}
