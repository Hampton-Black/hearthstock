import HearthstockCore
import SwiftUI

@main
struct Hearthstock: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .tint(.hsTint)
        }
    }
}

/// Opens the database, then hands the session to the rest of the app through the environment.
/// A database that won't open or migrate is shown as text, not a crash.
struct RootView: View {
    private enum Phase {
        case starting
        case ready(AppSession)
        case failed(String)
    }

    @State private var phase: Phase = .starting
    @State private var today = Today()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            switch phase {
            case .starting:
                ProgressView().task { await start() }
            case .ready(let session):
                MainTabView()
                    .id(session.siteID)
                    .environment(session)
                    .environment(today)
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
        .task { await today.watchForDayChanges() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { today.refresh() }
        }
    }

    private func start() async {
        do {
            let (services, site) = try await AppServices.start()
            phase = .ready(AppSession(services: services, siteID: site.id))
        } catch {
            phase = .failed(String(describing: error))
        }
    }
}
