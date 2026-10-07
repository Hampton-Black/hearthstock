import HearthstockCore
import SwiftUI

@MainActor @Observable
final class DashboardModel: RunwayInputsModel {
    var phase: FeedPhase = .loading
    var inputs: RunwayInputs?
    var today: CalendarDate = .today()
    private(set) var runway: SiteRunway?
    private let profiles: ShelfLifeProfileTable

    init(profiles: ShelfLifeProfileTable) {
        self.profiles = profiles
    }

    func recompute() {
        guard let inputs else { return }
        runway = RunwayCalculator.runway(for: inputs, profiles: profiles, on: today)
    }
}

struct DashboardView: View {
    @Environment(AppSession.self) private var session
    @Environment(Today.self) private var today
    @State private var model: DashboardModel?

    var body: some View {
        NavigationStack {
            Group {
                if let model {
                    FeedContent(phase: model.phase) {
                        List {
                            if let effective = model.runway?.effective {
                                Text("You could last about \(DaysText(effective).full)")
                            } else {
                                Text("Add your household to compute runway")
                            }
                        }
                        .hearthList()
                    }
                }
            }
            .navigationTitle("Runway")
            .addItemButton()
        }
        .task {
            let model = DashboardModel(profiles: session.services.profiles)
            self.model = model
            await model.subscribe(session.services, siteID: session.siteID)
        }
        .onChange(of: today.date, initial: true) { _, day in model?.setToday(day) }
    }
}
