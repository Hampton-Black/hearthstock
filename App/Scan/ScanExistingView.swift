import HearthstockCore
import SwiftUI

/// "Already in your inventory" (Scan-Existing): the product's lots here with their dates and states. Adding to one
/// keeps its acquired date; "Different date: start a new lot" (the default) continues to the add form.
struct ScanExistingView: View {
    let product: Product
    let lots: [LotStatus]
    let model: ScanFlowModel
    let differentDate: (AddLotModel.Preset) -> Void

    @Environment(Today.self) private var today
    @Environment(\.dismiss) private var dismiss
    /// Nil is "Different date: start a new lot".
    @State private var chosen: LotID?
    @State private var count = 1
    @State private var amount: Double?
    @State private var writeError: String?
    @State private var saving = false

    private var isCount: Bool { product.unitKind == .count }
    private var addAmount: Double? { isCount ? Double(count) : amount.flatMap { $0 > 0 ? $0 : nil } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(lots) { status in
                        Button { chosen = status.id } label: { lotRow(status).contentShape(Rectangle()) }
                            .accessibilityAddTraits(chosen == status.id ? .isSelected : [])
                    }
                } header: {
                    Text("Same date as one of these")
                }

                Section {
                    Button { chosen = nil } label: {
                        HStack {
                            Label("Different date: start a new lot", systemImage: "calendar.badge.plus")
                                .foregroundStyle(Color.hsInk)
                            Spacer()
                            if chosen == nil { Image(systemName: "checkmark").foregroundStyle(Color.hsTint) }
                        }
                        .contentShape(Rectangle())
                    }
                    .accessibilityAddTraits(chosen == nil ? .isSelected : [])
                }

                if chosen != nil {
                    Section {
                        if isCount {
                            Stepper(value: $count, in: 1...999) {
                                LabeledContent("Adding") { Text("\(count)").numeric().foregroundStyle(Color.hsInk) }
                            }
                        } else {
                            LabeledContent("Adding") {
                                HStack {
                                    TextField("Amount", value: $amount, format: .number)
                                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                                    Text(product.baseUnit.symbol).foregroundStyle(Color.hsInk2)
                                }
                            }
                        }
                    } footer: {
                        Text("Added to the lot you picked; it keeps its acquired date.")
                    }
                }
            }
            .hearthList()
            .navigationTitle("Already have this")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(chosen == nil ? "Next" : "Add") { confirm() }
                        .disabled(saving || (chosen != nil && addAmount == nil))
                }
            }
            .safeAreaInset(edge: .top) {
                Text(product.name)
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20).padding(.top, 8)
            }
        }
        .errorAlert($writeError)
    }

    private func lotRow(_ status: LotStatus) -> some View {
        HStack(spacing: 12) {
            Image(systemName: chosen == status.id ? "largecircle.fill.circle" : "circle")
                .foregroundStyle(chosen == status.id ? Color.hsTint : Color.hsInk3)
            VStack(alignment: .leading, spacing: 2) {
                Text(LotText.detailLine(status)).foregroundStyle(Color.hsInk).numeric()
                Text(LotText.path(status)).font(.subheadline).foregroundStyle(Color.hsInk2)
            }
            Spacer()
            if let state = status.state { StateBadge(state: state) }
        }
    }

    private func confirm() {
        guard let chosen, let lot = lots.first(where: { $0.id == chosen }) else {
            dismiss()
            differentDate(AddLotModel.Preset(product: .existing(product), locationID: model.locationID))
            return
        }
        guard let addAmount else { return }
        saving = true
        Task {
            do {
                try await model.add(addAmount, to: lot)
                dismiss()
            } catch {
                writeError = ErrorText.describe(error)
            }
            saving = false
        }
    }
}
