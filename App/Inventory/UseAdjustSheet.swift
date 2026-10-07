import HearthstockCore
import SwiftUI

/// Use some of a lot (in any unit of its product's kind), or Adjust it to what's actually left.
struct UseAdjustSheet: View {
    enum Mode: Hashable {
        case use
        case adjust
    }

    let lotID: LotID
    @State var mode: Mode

    @Environment(AppSession.self) private var session
    @Environment(Today.self) private var today
    @Environment(\.dismiss) private var dismiss
    @State private var model: LotModel?
    @State private var amount: Double?
    @State private var unit: QuantityUnit?
    @State private var writeError: String?
    @State private var prefilled = false

    var body: some View {
        NavigationStack {
            Group {
                if let status = model?.status, let product = status.product {
                    content(status, product: product)
                } else if model?.phase == .live {
                    ContentUnavailableView("This item is used up or was deleted", systemImage: "shippingbox")
                } else {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.hsBg)
            .navigationTitle(mode == .use ? "Use some" : "Adjust")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
        .task {
            let model = LotModel(lotID: lotID, profiles: session.services.profiles, today: today.date)
            self.model = model
            await model.subscribe(session.services, siteID: session.siteID)
        }
        .onChange(of: model?.status?.lot.quantity, initial: true) { _, _ in prefill() }
        .errorAlert($writeError)
    }

    private func prefill() {
        guard !prefilled, let status = model?.status, let product = status.product else { return }
        prefilled = true
        unit = product.baseUnit
        switch mode {
        case .use: amount = product.unitKind == .count ? 1 : nil
        case .adjust: amount = status.lot.quantity
        }
    }

    @ViewBuilder
    private func content(_ status: LotStatus, product: Product) -> some View {
        let unit = unit ?? product.baseUnit
        let available = (try? Quantity(value: status.lot.quantity, unit: product.baseUnit).converted(to: unit).value) ?? status.lot.quantity
        let base = amount.flatMap { try? QuantityEntry(value: $0, unit: unit).baseAmount(for: product.unitKind, allowZero: mode == .adjust) }
        let over = mode == .use && (base ?? 0) > status.lot.quantity + 1e-9

        VStack(spacing: 16) {
            Picker("Mode", selection: $mode) {
                Text("Use some").tag(Mode.use)
                Text("Adjust").tag(Mode.adjust)
            }
            .pickerStyle(.segmented)
            .onChange(of: mode) { _, newMode in
                amount = newMode == .adjust ? available : (product.unitKind == .count ? 1 : nil)
            }

            Text("\(product.name) · \(LotText.path(status)) · **\(QuantityText.format(status.lot.quantity, product.baseUnit))** on hand")
                .font(.subheadline).foregroundStyle(Color.hsInk2).multilineTextAlignment(.center).numeric()

            Text(mode == .use ? "How much did you use?" : "How much is left?").font(.headline)

            HStack(spacing: 12) {
                stepButton("minus") { amount = max(0, (amount ?? 0) - 1) }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    TextField("0", value: $amount, format: .number.precision(.fractionLength(0...3)))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .font(.system(size: 44, weight: .bold)).numeric()
                        .fixedSize()
                    Text(unit.symbol).font(.title3).foregroundStyle(Color.hsInk2)
                }
                .frame(maxWidth: .infinity)
                stepButton("plus") { amount = (amount ?? 0) + 1 }
            }

            let units = QuantityUnit.entryUnits(for: product.unitKind)
            if units.count > 1 {
                Picker("Unit", selection: Binding(get: { unit }, set: { newUnit in
                    // Keep the same physical amount when the unit changes.
                    if let value = amount, let converted = try? Quantity(value: value, unit: unit).converted(to: newUnit) {
                        amount = (converted.value * 1000).rounded() / 1000
                    }
                    self.unit = newUnit
                })) {
                    ForEach(units, id: \.self) { Text($0.symbol).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            Group {
                if over {
                    VStack(spacing: 8) {
                        Text("Only \(QuantityText.format(available, unit)) is left.").foregroundStyle(Color.hsAmber)
                        Button("Use all \(QuantityText.format(available, unit))") { amount = available }
                    }
                } else if let base {
                    let left = mode == .use ? status.lot.quantity - base : base
                    if left <= 1e-9 {
                        Text("It will be marked used up and kept in your history.")
                    } else {
                        Text("\(QuantityText.format(left, product.baseUnit)) left after this").numeric()
                    }
                }
            }
            .font(.subheadline)
            .foregroundStyle(Color.hsInk2)

            Spacer()

            Button(primaryTitle(base: base, unit: unit)) {
                guard let base else { return }
                save(status, base: base)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(base == nil || over || (mode == .use && base == 0))
            .opacity(base == nil || over ? 0.5 : 1)
        }
        .padding(16)
    }

    private func stepButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title2.weight(.semibold))
                .frame(width: 56, height: 56)
                .background(Color.hsTrack, in: RoundedRectangle(cornerRadius: 14))
                .foregroundStyle(Color.hsInk)
        }
        .accessibilityLabel(symbol == "plus" ? "One more" : "One less")
    }

    private func primaryTitle(base: Double?, unit: QuantityUnit) -> String {
        guard let amount, base != nil else { return mode == .use ? "Use" : "Save" }
        return mode == .use ? "Use \(QuantityText.format(amount, unit))" : "Set to \(QuantityText.format(amount, unit))"
    }

    private func save(_ status: LotStatus, base: Double) {
        let lots = session.services.lots
        Task {
            do {
                switch mode {
                case .use: try await lots.consume(status.lot.id, amount: base)
                case .adjust: try await lots.save(status.lot.adjusted(toRemaining: base))
                }
                dismiss()
            } catch {
                writeError = ErrorText.describe(error)
            }
        }
    }
}
