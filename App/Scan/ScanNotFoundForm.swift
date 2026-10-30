import HearthstockCore
import SwiftUI

/// "We don't know this one yet" (Scan-NotFound): the barcode is kept, and only the minimum is asked for: name,
/// category, and calories per item for food. Next continues to the normal add form; Rescan goes back to the camera.
struct ScanNotFoundForm: View {
    let reason: LookupUnavailableReason?
    /// The product so far, with its calorie answers and name guess (Slice 5), for the add form.
    let next: (NewProductEntry) -> Void

    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var entry: NewProductEntry
    @State private var scanningLabel = false

    init(draft: ProductDraft, reason: LookupUnavailableReason?, next: @escaping (NewProductEntry) -> Void) {
        _entry = State(initialValue: NewProductEntry(draft: draft, amount: draft.unitKind == .count ? 1 : nil))
        self.reason = reason
        self.next = next
    }

    private var draft: ProductDraft { entry.draft }

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
                        TextField("Black beans, 15 oz", text: Binding(get: { draft.name }, set: { name in
                            entry.setName(
                                name, guesser: session.services.nameProfiles, profiles: session.services.profiles)
                        }))
                        .multilineTextAlignment(.trailing)
                    }
                    Picker("Category", selection: Binding(get: { draft.category }, set: { category in
                        entry.setCategory(
                            category, guesser: session.services.nameProfiles, profiles: session.services.profiles)
                    })) {
                        ForEach(SupplyCategory.allCases, id: \.self) { Label($0.title, systemImage: $0.symbol).tag($0) }
                    }
                    if entry.naming.guess != nil || entry.naming.profilePicked {
                        NameGuessLine(
                            profileKey: draft.shelfLifeProfileKey, guessed: entry.naming.guess != nil,
                            profiles: session.services.profiles, pick: { entry.pickProfile($0) })
                    }
                    if draft.category == .food {
                        CaloriesRow(
                            entry: entry.calories, unitKind: draft.unitKind,
                            update: { change in entry.updateCalories(change) }, scanLabel: { scanningLabel = true })
                    }
                } footer: {
                    Text(draft.category == .food
                        ? "Counted per item (can, jar, bottle). Leave calories empty and it shows as missing calories until you add them."
                        : "Counted per item. You can change how it's measured on the next screen.")
                }
                Section {
                    LabeledContent("Barcode") { Text(draft.barcode ?? "").numeric().foregroundStyle(Color.hsInk2) }
                }
            }
            .hearthList()
            .sheet(isPresented: $scanningLabel) {
                NutritionLabelScannerSheet { reading in
                    var preview = entry
                    preview.updateCalories { $0.useLabel(reading) }
                    return preview.draft.kcalPerBaseUnit.map { (kcal: $0, unitKind: preview.draft.unitKind) }
                } onUse: { reading in
                    entry.updateCalories { $0.useLabel(reading) }
                }
            }
            .navigationTitle("Not found")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Rescan") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Next") {
                        dismiss()
                        next(entry)
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
}
