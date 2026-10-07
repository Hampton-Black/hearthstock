import HearthstockCore
import SwiftUI

@MainActor @Observable
final class SettingsModel: RunwayInputsModel {
    var phase: FeedPhase = .loading
    var inputs: RunwayInputs?
    var today: CalendarDate = .today()

    func recompute() {}
}

struct SettingsView: View {
    @Environment(AppSession.self) private var session
    @State private var model = SettingsModel()
    @State private var writeError: String?

    var body: some View {
        NavigationStack {
            FeedContent(phase: model.phase) {
                List {
                    Section("Site") {
                        LabeledContent("Name", value: model.inputs?.site.name ?? "")
                    }
                    #if DEBUG
                    Section("Developer · Debug builds only") {
                        Button("Load sample pantry") { Task { await loadSamplePantry() } }
                    }
                    #endif
                }
                .hearthList()
            }
            .navigationTitle("Settings")
        }
        .task { await model.subscribe(session.services, siteID: session.siteID) }
        .errorAlert($writeError)
    }

    #if DEBUG
    private func loadSamplePantry() async {
        do {
            try await SamplePantry.load(into: session.services, siteID: session.siteID)
        } catch {
            writeError = ErrorText.describe(error)
        }
    }
    #endif
}
