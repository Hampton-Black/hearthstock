import HearthstockCore
import SwiftUI

/// Settings → Online lookup (Slice 4 Decisions 6–8): the switch, how many answers are saved, and a way to clear them.
struct OnlineLookupSection: View {
    @Environment(AppSession.self) private var session
    @State private var enabled = Preferences.onlineLookupEnabled
    @State private var saved: Int?
    @State private var confirmingClear = false
    @State private var writeError: String?

    var body: some View {
        Section {
            Toggle("Look up unknown barcodes", isOn: $enabled)
                .onChange(of: enabled) { _, value in Preferences.onlineLookupEnabled = value }
            LabeledContent("Saved lookups") {
                Text(saved.map { "\($0)" } ?? "–").numeric()
            }
            Button("Clear saved lookups", role: .destructive) { confirmingClear = true }
                .disabled((saved ?? 0) == 0)
        } header: {
            Text("Online lookup")
        } footer: {
            Text("Unknown barcodes are looked up in Open Food Facts. Only the barcode is sent, and each one is sent once: the answer is saved on this phone and used for every later scan.")
        }
        .task { await refresh() }
        .confirmationDialog("Clear saved lookups?", isPresented: $confirmingClear, titleVisibility: .visible) {
            Button(saved == 1 ? "Clear 1 lookup" : "Clear \(saved ?? 0) lookups", role: .destructive) {
                Task { await clear() }
            }
        } message: {
            Text("Barcodes you scan after this are looked up online again. Your products and items don't change.")
        }
        .errorAlert($writeError, title: "Couldn't clear")
    }

    private func refresh() async {
        saved = try? await session.services.lookupCache.count()
    }

    private func clear() async {
        do {
            try await session.services.lookupCache.clear()
        } catch {
            writeError = ErrorText.describe(error)
        }
        await refresh()
    }
}
