import HearthstockCore
import SwiftUI

/// "We don't know this one yet" (Scan-NotFound): the barcode is kept, and only the minimum is asked for: name,
/// category, and calories per item for food. Next continues to the normal add form; Rescan goes back to the camera.
struct ScanNotFoundForm: View {
    let reason: LookupUnavailableReason?
    let next: (ProductDraft) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: ProductDraft

    init(draft: ProductDraft, reason: LookupUnavailableReason?, next: @escaping (ProductDraft) -> Void) {
        _draft = State(initialValue: draft)
        self.reason = reason
        self.next = next
    }

    private var canContinue: Bool { !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label {
                        Text(message)
                    } icon: {
                        Image(systemName: reason == .offline ? "wifi.slash" : "questionmark.circle")
                    }
                    .foregroundStyle(Color.hsInk2)
                    .listRowBackground(Color.hsTrack)
                }
                Section {
                    LabeledContent("Name") {
                        TextField("Black beans, 15 oz", text: $draft.name).multilineTextAlignment(.trailing)
                    }
                    Picker("Category", selection: Binding(get: { draft.category }, set: { setCategory($0) })) {
                        ForEach(SupplyCategory.allCases, id: \.self) { Label($0.title, systemImage: $0.symbol).tag($0) }
                    }
                    if draft.category == .food {
                        LabeledContent("Calories per item") {
                            TextField("Optional", value: $draft.kcalPerBaseUnit, format: .number)
                                .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                        }
                    }
                } footer: {
                    Text(draft.category == .food
                        ? "Counted per item (can, jar, bottle). Calories per item = calories per serving × servings per container. Leave it empty and it shows as missing calories until you add it."
                        : "Counted per item. You can change how it's measured on the next screen.")
                }
                Section {
                    LabeledContent("Barcode") { Text(draft.barcode ?? "").numeric().foregroundStyle(Color.hsInk2) }
                }
            }
            .hearthList()
            .navigationTitle("Not found")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Rescan") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Next") {
                        dismiss()
                        next(draft)
                    }
                    .disabled(!canContinue)
                }
            }
        }
    }

    private var message: String {
        guard let reason else { return "Open Food Facts doesn't know this barcode. Add what you know; the barcode is kept." }
        return "\(LookupText.unavailable(reason)) You can fill this in now, and a later lookup can fill in what's missing."
    }

    private func setCategory(_ category: SupplyCategory) {
        let oldDefault = ProductDraft.defaultProfileKey(for: draft.category)
        draft.category = category
        if draft.shelfLifeProfileKey == oldDefault {
            draft.shelfLifeProfileKey = ProductDraft.defaultProfileKey(for: category)
        }
        if category != .food { draft.kcalPerBaseUnit = nil }
        draft.potableWaterGalPerBaseUnit = nil
    }
}
