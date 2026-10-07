import HearthstockCore
import SwiftUI

@MainActor @Observable
final class InventoryModel: RunwayInputsModel {
    var phase: FeedPhase = .loading
    var inputs: RunwayInputs?
    var today: CalendarDate = .today()
    var query = InventoryQuery() { didSet { recompute() } }
    private(set) var sections: [InventorySection] = []
    private let profiles: ShelfLifeProfileTable

    init(profiles: ShelfLifeProfileTable) {
        self.profiles = profiles
    }

    func recompute() {
        guard let inputs else { return }
        let statuses = LotStatusEvaluator.statuses(for: inputs, profiles: profiles, on: today)
        sections = Inventory.sections(statuses, locations: inputs.locations, query: query)
    }
}

struct InventoryView: View {
    @Environment(AppSession.self) private var session
    @Environment(Today.self) private var today
    @State private var model: InventoryModel?

    var body: some View {
        NavigationStack {
            Group {
                if let model {
                    FeedContent(phase: model.phase) {
                        List(model.sections) { section in
                            Section {
                                ForEach(section.lots) { status in
                                    HStack {
                                        Text(status.product?.name ?? "Unknown product")
                                        Spacer()
                                        if let state = status.state { StateBadge(state: state) }
                                    }
                                }
                            }
                        }
                        .hearthList()
                    }
                }
            }
            .navigationTitle("Inventory")
            .addItemButton()
        }
        .task {
            let model = InventoryModel(profiles: session.services.profiles)
            self.model = model
            await model.subscribe(session.services, siteID: session.siteID)
        }
        .onChange(of: today.date, initial: true) { _, day in model?.setToday(day) }
    }
}
