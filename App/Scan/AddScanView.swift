import HearthstockCore
import SwiftUI

/// Add · scan's state: the scanner, the site's data, and the step a resolved scan leads to. Every decision about
/// what a barcode means is `ScanResolution`'s; this only runs the lookup and opens the next screen.
@MainActor @Observable
final class ScanFlowModel: RunwayInputsModel {
    /// The screen a scan opens over the camera.
    struct Step: Identifiable {
        enum Kind {
            /// "Already in your inventory": lots of this product at this site.
            case existing(Product, lots: [LotStatus])
            /// The add form, starting from what the scan found.
            case add(AddLotModel.Preset)
            /// "We don't know this one yet", with the reason when the lookup couldn't run.
            case notFound(ProductDraft, reason: LookupUnavailableReason?)
        }

        let id = UUID()
        let barcode: Barcode?
        let kind: Kind
    }

    var phase: FeedPhase = .loading
    var inputs: RunwayInputs?
    var today: CalendarDate
    let scanner = ScannerModel()
    var step: Step?
    /// Opens when the current step's sheet has closed (a sheet can't replace itself).
    var nextStep: Step?
    var locationID: LocationID?
    /// The barcode being looked up online, while it is.
    private(set) var lookingUp: Barcode?
    /// A short confirmation over the camera ("Added 2 to Black beans").
    private(set) var banner: String?
    private(set) var locationPaths: [[Location]] = []

    private let services: AppServices
    private let siteID: SiteID

    init(services: AppServices, siteID: SiteID, today: CalendarDate) {
        self.services = services
        self.siteID = siteID
        self.today = today
        scanner.onEvent = { [weak self] event in
            switch event {
            case .scan(let code), .repeat(let code): self?.scanned(code)
            }
        }
    }

    func recompute() {
        locationPaths = LocationTree.paths(inputs?.locations ?? [])
        let ids = Set(locationPaths.map { $0.last!.id })
        if let id = locationID, !ids.contains(id) { locationID = nil }
        if locationID == nil {
            locationID = Preferences.lastUsedLocation(siteID: siteID).flatMap { ids.contains($0) ? $0 : nil }
                ?? locationPaths.first?.last?.id
        }
    }

    var locationName: String {
        locationPaths.first { $0.last?.id == locationID }?.map(\.name).joined(separator: " › ") ?? "Choose a location"
    }

    func setLocation(_ id: LocationID) {
        locationID = id
        Preferences.setLastUsedLocation(id, siteID: siteID)
    }

    private func scanned(_ code: Barcode) {
        Task { await resolve(code) }
    }

    /// Resolves locally, then (for an unknown barcode) asks the cached-or-online lookup and resolves again.
    func resolve(_ code: Barcode) async {
        guard let inputs else {
            scanner.resume()
            return
        }
        let statuses = LotStatusEvaluator.statuses(for: inputs, profiles: services.profiles, on: today)
        var outcome = ScanResolution.resolve(code, products: inputs.products, statuses: statuses, lookup: nil)
        var lookedUp: LookedUpProduct?
        if case .lookingUp = outcome {
            lookingUp = code
            let result = await services.lookup.lookup(code)
            lookingUp = nil
            let lookup: ScanLookup
            switch result {
            case .found(let product):
                lookedUp = product
                lookup = .found(OpenFoodFacts.draft(
                    from: product, barcode: code, categories: services.offCategories, profiles: services.profiles))
            case .notFound: lookup = .notFound
            case .unavailable(let reason): lookup = .unavailable(reason)
            }
            outcome = ScanResolution.resolve(code, products: inputs.products, statuses: statuses, lookup: lookup)
        }
        switch outcome {
        case .known(let product, let lots) where lots.isEmpty:
            step = Step(barcode: code, kind: .add(AddLotModel.Preset(product: .existing(product), locationID: locationID)))
        case .known(let product, let lots):
            step = Step(barcode: code, kind: .existing(product, lots: lots))
        case .found(let draft):
            step = Step(barcode: code, kind: .add(AddLotModel.Preset(
                product: .new(draft), locationID: locationID,
                note: "Filled in from Open Food Facts. Check the name and calories.", lookedUp: lookedUp)))
        case .notFound(let draft):
            step = Step(barcode: code, kind: .notFound(draft, reason: nil))
        case .lookupUnavailable(let draft, let reason):
            step = Step(barcode: code, kind: .notFound(draft, reason: reason))
        case .lookingUp:
            scanner.resume()
        }
    }

    /// "Type it in": the manual add form, into the chosen location.
    func typeItIn() {
        step = Step(barcode: nil, kind: .add(AddLotModel.Preset(product: nil, locationID: locationID)))
    }

    /// Continue to the add form once the current sheet has closed.
    func continueToAdd(_ preset: AddLotModel.Preset, barcode: Barcode?) {
        nextStep = Step(barcode: barcode, kind: .add(preset))
    }

    /// The current step's sheet closed: open the next one, or go back to scanning.
    func stepClosed() {
        if let nextStep {
            self.nextStep = nil
            step = nextStep
        } else {
            scanner.resume()
        }
    }

    /// "Same date as one of these": adds to that lot in one write.
    func add(_ amount: Double, to lot: LotStatus) async throws {
        _ = try await services.lots.add(lot.id, amount: amount)
        Preferences.setLastUsedLocation(lot.lot.locationID, siteID: siteID)
        show("Added \(QuantityText.format(amount, lot.product?.baseUnit ?? .count)) to \(lot.product?.name ?? "the lot")")
    }

    private func show(_ text: String) {
        banner = text
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            if banner == text { banner = nil }
        }
    }
}

/// Add · scan: the camera opens first, with "Type it in" one tap away (Slice 4 Decision 14).
struct AddScanView: View {
    @Environment(AppSession.self) private var session
    @Environment(Today.self) private var today
    @Environment(\.dismiss) private var dismiss
    @State private var model: ScanFlowModel?
    @State private var walking: WalkStart?
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            // While a walk runs over this screen, its camera stops: one scanner at a time.
            if let model, walking == nil {
                content(model)
            } else {
                Color.hsCameraBg.ignoresSafeArea()
            }
        }
        .task {
            let model = ScanFlowModel(services: session.services, siteID: session.siteID, today: today.date)
            self.model = model
            await model.subscribe(session.services, siteID: session.siteID)
        }
        .onChange(of: today.date) { _, day in model?.setToday(day) }
        .fullScreenCover(item: $walking) { start in
            PantryWalkView(start: start) { next in
                walking = WalkStart(locationID: next)
            } finish: {
                walking = nil
                dismiss()
            }
        }
    }

    @ViewBuilder
    private func content(_ model: ScanFlowModel) -> some View {
        @Bindable var model = model
        CameraScreen(title: "Add item", scanner: model.scanner, showsReticle: model.lookingUp == nil) {
            VStack(spacing: 12) {
                if let code = model.lookingUp {
                    HStack(spacing: 10) {
                        ProgressView().tint(Color.hsCameraInk)
                        Text("Looking up \(code.rawValue)…").font(.subheadline.monospacedDigit())
                    }
                    .padding(.horizontal, 16).frame(minHeight: 48)
                    .background(Color.hsCameraControl, in: Capsule())
                }
                if let banner = model.banner {
                    Label(banner, systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 16).frame(minHeight: 44)
                        .background(Color.hsCameraControl, in: Capsule())
                        .transition(.opacity)
                }
                locationChip(model)
                let layout = typeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(spacing: 12)) : AnyLayout(HStackLayout(spacing: 12))
                layout {
                    Button { model.typeItIn() } label: {
                        Label("Type it in", systemImage: "pencil").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(CameraPillStyle(prominent: true))
                    Button {
                        if let location = model.locationID { walking = WalkStart(locationID: location) }
                    } label: {
                        Label("Pantry walk", systemImage: "viewfinder").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(CameraPillStyle())
                    .disabled(model.locationID == nil)
                }
            }
        }
        .sheet(item: $model.step, onDismiss: { model.stepClosed() }) { step in
            stepView(step, model: model)
                .environment(\.colorScheme, .light)
        }
        .sensoryFeedback(.success, trigger: model.banner)
    }

    private func locationChip(_ model: ScanFlowModel) -> some View {
        Menu {
            ForEach(model.locationPaths, id: \.last!.id) { path in
                Button(path.map(\.name).joined(separator: " › ")) { model.setLocation(path.last!.id) }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "mappin.and.ellipse")
                (Text("Into ").foregroundStyle(Color.hsCameraInk2) + Text(model.locationName))
                    .multilineTextAlignment(.leading)
                Spacer()
                Image(systemName: "chevron.down").font(.caption.weight(.bold))
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
            .background(Color.hsCameraControl, in: RoundedRectangle(cornerRadius: 14))
        }
        .foregroundStyle(Color.hsCameraInk)
    }

    @ViewBuilder
    private func stepView(_ step: ScanFlowModel.Step, model: ScanFlowModel) -> some View {
        switch step.kind {
        case .existing(let product, let lots):
            ScanExistingView(product: product, lots: lots, model: model) { preset in
                model.continueToAdd(preset, barcode: step.barcode)
            }
        case .add(let preset):
            AddLotSheet(preset: preset, scanHooks: AddLotSheet.ScanHooks(
                scanAnother: {},
                finish: { dismiss() }))
        case .notFound(let draft, let reason):
            ScanNotFoundForm(draft: draft, reason: reason) { finished in
                model.continueToAdd(
                    AddLotModel.Preset(product: .new(finished), locationID: model.locationID), barcode: step.barcode)
            }
        }
    }
}
