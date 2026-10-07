import HearthstockCore
import SwiftUI

@main
struct Hearthstock: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

/// Opens the database, then hands the repositories to the rest of the app through the environment.
/// A database that won't open or migrate is shown as text, not a crash.
struct RootView: View {
    private enum Phase {
        case starting
        case ready(AppServices, Site)
        case failed(String)
    }

    @State private var phase: Phase = .starting

    var body: some View {
        switch phase {
        case .starting:
            ProgressView().task { await start() }
        case .ready(let services, let site):
            ContentView(site: site).environment(\.services, services)
        case .failed(let message):
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Couldn't open the database").font(.headline)
                    Text(message).font(.callout.monospaced()).textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
        }
    }

    private func start() async {
        do {
            let (services, site) = try await AppServices.start()
            phase = .ready(services, site)
        } catch {
            phase = .failed(String(describing: error))
        }
    }
}
