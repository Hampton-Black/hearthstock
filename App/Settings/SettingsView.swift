import HearthstockCore
import SwiftUI

@MainActor @Observable
final class SettingsModel: RunwayInputsModel {
    var phase: FeedPhase = .loading
    var inputs: RunwayInputs?
    var today: CalendarDate = .today()
    /// Location paths in tree order, for the indented list.
    private(set) var locationPaths: [[Location]] = []

    func recompute() {
        locationPaths = LocationTree.paths(inputs?.locations ?? [])
    }

    func kit(for location: Location) -> Kit? {
        inputs?.kits.first { $0.locationID == location.id || $0.id == location.kitID }
    }
}

struct SettingsView: View {
    @Environment(AppSession.self) private var session
    @State private var model = SettingsModel()
    @State private var writeError: String?
    @State private var siteName = ""
    @State private var addingPerson = false
    @State private var addingLocation = false
    @State private var backup = BackupController()

    var body: some View {
        NavigationStack {
            FeedContent(phase: model.phase) {
                if let inputs = model.inputs {
                    form(inputs)
                }
            }
            .background(Color.hsBg)
            .navigationTitle("Settings")
            .navigationDestination(for: PersonID.self) { id in
                if let person = model.inputs?.occupants.first(where: { $0.id == id }) {
                    PersonForm(person: person, isNew: false)
                }
            }
            .navigationDestination(for: LocationID.self) { id in
                if let location = model.inputs?.locations.first(where: { $0.id == id }), let inputs = model.inputs {
                    LocationForm(location: location, kit: model.kit(for: location), inputs: inputs, isNew: false)
                }
            }
        }
        .task { await model.subscribe(session.services, siteID: session.siteID) }
        .backupPresentations(backup, siteName: model.inputs?.site.name ?? "Site")
        .onChange(of: model.inputs?.site.name, initial: true) { _, name in siteName = name ?? "" }
        .errorAlert($writeError)
        .sheet(isPresented: $addingPerson) {
            NavigationStack {
                PersonForm(person: Person(siteID: session.siteID, name: ""), isNew: true)
            }
        }
        .sheet(isPresented: $addingLocation) {
            if let inputs = model.inputs {
                NavigationStack {
                    LocationForm(
                        location: Location(siteID: session.siteID, name: ""), kit: nil, inputs: inputs, isNew: true)
                }
            }
        }
    }

    private func form(_ inputs: RunwayInputs) -> some View {
        List {
            Section {
                LabeledContent("Name") {
                    TextField("Site name", text: $siteName)
                        .multilineTextAlignment(.trailing)
                        .submitLabel(.done)
                        .onSubmit { saveSite(inputs.site, name: siteName) }
                }
                Stepper(value: noticeWindow(inputs.site), in: 1...365) {
                    LabeledContent("Use soon notice") {
                        Text("\(inputs.site.noticeWindowDays) days").numeric().foregroundStyle(Color.hsInk)
                    }
                }
            } header: {
                Text("Site")
            } footer: {
                Text("Items move to Use soon this many days before their printed date. They still count fully toward runway.")
            }

            Section {
                ForEach(inputs.occupants) { person in
                    NavigationLink(value: person.id) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(person.name)
                            Text(person.needsText).font(.subheadline).foregroundStyle(Color.hsInk2).numeric()
                        }
                    }
                }
                Button("Add person", systemImage: "plus") { addingPerson = true }
            } header: {
                Text("Household")
            } footer: {
                Text("New people start at 2,000 kcal and 1 gal of water a day.")
            }

            Section {
                ForEach(model.locationPaths, id: \.last!.id) { path in
                    NavigationLink(value: path.last!.id) {
                        LocationRow(path: path, isKit: model.kit(for: path.last!) != nil || path.last!.kitID != nil)
                    }
                }
                Button("Add location", systemImage: "plus") { addingLocation = true }
            } header: {
                Text("Locations")
            } footer: {
                Text("A place inside another (a shelf in the garage) inherits its climate unless you set its own.")
            }

            BackupSection(controller: backup, siteName: inputs.site.name)

            #if DEBUG
            Section("Developer · Debug builds only") {
                Button("Load sample pantry") { Task { await loadSamplePantry() } }
            }
            #endif
        }
        .hearthList()
    }

    private func noticeWindow(_ site: Site) -> Binding<Int> {
        Binding(
            get: { site.noticeWindowDays },
            set: { days in
                var updated = site
                updated.noticeWindowDays = days
                save(updated)
            })
    }

    private func saveSite(_ site: Site, name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            siteName = site.name
            return
        }
        var updated = site
        updated.name = trimmed
        save(updated)
    }

    private func save(_ site: Site) {
        Task {
            do { try await session.services.sites.save(site) } catch { writeError = ErrorText.describe(error) }
        }
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

/// One location in the tree: indented by depth, with its climate tag (or "Inherits") and a Kit tag.
private struct LocationRow: View {
    let path: [Location]
    let isKit: Bool

    var body: some View {
        let location = path.last!
        HStack(spacing: 6) {
            if path.count > 1 {
                Text("└").foregroundStyle(Color.hsInk3).padding(.leading, CGFloat(path.count - 2) * 18)
                    .accessibilityHidden(true)
            }
            Text(location.name).lineLimit(1)
            Spacer(minLength: 8)
            if isKit {
                tag("Kit", foreground: .hsTint, background: .hsTintSoft)
            } else if let climate = location.climateClass {
                tag(climate.shortTitle, foreground: climate == .hot || climate == .vehicle ? .hsAmber : .hsInk2,
                    background: climate == .hot || climate == .vehicle ? .hsAmberBg : .hsTrack)
            } else if path.count > 1 {
                Text("Inherits").font(.footnote.weight(.semibold)).foregroundStyle(Color.hsInk3)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func tag(_ text: String, foreground: Color, background: Color) -> some View {
        Text(text)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(foreground)
            .padding(.vertical, 2)
            .padding(.horizontal, 8)
            .background(background, in: Capsule())
    }
}
