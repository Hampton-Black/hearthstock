import HearthstockCore
import SwiftUI

/// Smoke test for the persistence layer, not real UI: the site name, its lot count and its effective runway,
/// kept live from the database.
struct ContentView: View {
    let site: Site
    @Environment(\.services) private var services
    @State private var summary: RunwaySummary?
    @State private var errorText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let summary {
                Text("Site: \(summary.siteName)")
                Text("Lots: \(summary.lotCount)")
                Text("Runway: \(summary.runwayText)")
            } else {
                Text("Site: \(site.name)")
            }
            if let errorText {
                Text(errorText).foregroundStyle(.red).textSelection(.enabled)
            }
            #if DEBUG
            if summary?.isEmpty == true {
                Button("Load sample pantry") { Task { await loadSamplePantry() } }
                    .buttonStyle(.borderedProminent)
            }
            #endif
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .task { await observe() }
    }

    private func observe() async {
        guard let services else { return }
        do {
            for try await inputs in services.runwayInputs.observeRunwayInputs(siteID: site.id) {
                summary = RunwaySummary(inputs: inputs, profiles: services.profiles, today: .today())
            }
        } catch {
            errorText = String(describing: error)
        }
    }

    #if DEBUG
    private func loadSamplePantry() async {
        guard let services else { return }
        do {
            try await SamplePantry.load(into: services, site: site)
            errorText = nil
        } catch {
            errorText = String(describing: error)
        }
    }
    #endif
}
