import Foundation
import HearthstockCore

/// A pantry walk's state: the camera stays open, the location is locked, each Add saves at once (Slice 4 Decision
/// 15) and is recorded in a Core `PantryWalk` so Undo can reverse it. Resolution is `ScanResolution`'s, as in Add ·
/// scan; the walk only shows it as a card over the camera.
@MainActor @Observable
final class PantryWalkModel: RunwayInputsModel {
    /// The confirm card for one scan.
    struct Card: Identifiable {
        enum Subject {
            case known(Product)
            /// From a lookup (found) or blank (not found / unavailable, with the reason). The entry keeps the draft,
            /// the amount, the calorie answers and the name guess in step (Slice 5).
            case new(NewProductEntry, found: Bool, reason: LookupUnavailableReason?)
        }

        let id = UUID()
        let barcode: Barcode
        var subject: Subject
        private var knownAmount: Double?
        var printed: AddLotModel.PrintedDate = .unset
        var estimateMonths: Int?
        /// "Different date" opens the card straight into the date sheet.
        var opensDateSheet = false
        /// Name, category and calories are asked for on the card: not found, or found with no name (Open Food
        /// Facts had little but the barcode). Set when the card opens, so typing a name doesn't change the layout.
        let asksForBasics: Bool

        init(barcode: Barcode, subject: Subject) {
            self.barcode = barcode
            self.subject = subject
            switch subject {
            case .known: asksForBasics = false
            case .new(let entry, let found, _):
                asksForBasics = !found || entry.draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
        }

        /// In the product's base unit; count products start at 1.
        var amount: Double? {
            get {
                if case .new(let entry, _, _) = subject { entry.amount } else { knownAmount }
            }
            set {
                if case .new(var entry, let found, let reason) = subject {
                    entry.amount = newValue
                    subject = .new(entry, found: found, reason: reason)
                } else {
                    knownAmount = newValue
                }
            }
        }

        /// The new product's entry, when there is one.
        var entry: NewProductEntry? {
            if case .new(let entry, _, _) = subject { entry } else { nil }
        }

        /// Changes the new product's entry; does nothing for a known product.
        mutating func modify(_ change: (inout NewProductEntry) -> Void) {
            guard case .new(var entry, let found, let reason) = subject else { return }
            change(&entry)
            subject = .new(entry, found: found, reason: reason)
        }

        var unitKind: UnitKind {
            switch subject {
            case .known(let product): product.unitKind
            case .new(let entry, _, _): entry.draft.unitKind
            }
        }

        var name: String {
            switch subject {
            case .known(let product): product.name
            case .new(let entry, _, _): entry.draft.name
            }
        }

        var category: SupplyCategory {
            switch subject {
            case .known(let product): product.category
            case .new(let entry, _, _): entry.draft.category
            }
        }

        var profileKey: ShelfLifeProfileKey {
            switch subject {
            case .known(let product): product.shelfLifeProfileKey
            case .new(let entry, _, _): entry.draft.shelfLifeProfileKey
            }
        }
    }

    /// "Scanned again": the code was added this walk.
    struct Duplicate: Identifiable {
        let id = UUID()
        let barcode: Barcode
        let product: Product
        let lotID: LotID
        /// What one more adds: the amount last added.
        let amount: Double
        /// The lot's quantity after adding one more.
        let total: Double
    }

    var phase: FeedPhase = .loading
    var inputs: RunwayInputs? {
        didSet { if startInputs == nil { startInputs = inputs } }
    }
    var today: CalendarDate
    let scanner = ScannerModel()
    private(set) var walk: PantryWalk
    /// The site as it was when the walk started, for the summary's before → after.
    private(set) var startInputs: RunwayInputs?
    var card: Card?
    var duplicate: Duplicate?
    private(set) var lookingUp: Barcode?
    /// "Added White rice · 20 lb", with Undo, until the next action.
    private(set) var lastAdded: String?
    /// Bumped on each save, for the success haptic.
    private(set) var saves = 0
    var writeError: String?

    let services: AppServices
    private let siteID: SiteID
    private var productByBarcode: [Barcode: ProductID] = [:]

    init(services: AppServices, siteID: SiteID, locationID: LocationID, today: CalendarDate) {
        self.services = services
        self.siteID = siteID
        self.today = today
        walk = PantryWalk(locationID: locationID, startedAt: .now)
        scanner.onEvent = { [weak self] event in self?.handle(event) }
    }

    func recompute() {}

    var locationName: String {
        guard let inputs else { return "" }
        return LocationTree.paths(inputs.locations).first { $0.last?.id == walk.locationID }?.last?.name ?? ""
    }

    func profile(for card: Card) -> ShelfLifeProfile? { services.profiles[card.profileKey] }

    // MARK: Scans

    /// Any code this walk already added opens "Scanned again", whether the scanner reported it as a repeat or as a
    /// new scan (a second can of the same item read after a pause, a code first seen while a card was open).
    private func handle(_ event: ScanDebouncer.Event) {
        let code: Barcode = switch event {
        case .scan(let code), .repeat(let code): code
        }
        if let duplicate = duplicate(for: code) {
            self.duplicate = duplicate
        } else {
            Task { await resolve(code) }
        }
    }

    private func duplicate(for code: Barcode) -> Duplicate? {
        guard let productID = productByBarcode[code], let lotID = walk.latestLot(of: productID),
              let inputs, let product = inputs.products.first(where: { $0.id == productID }),
              let lot = inputs.lots.first(where: { $0.id == lotID }),
              let last = walk.actions.last(where: { $0.lotID == lotID })
        else { return nil }
        let amount = product.unitKind == .count ? 1 : last.amount
        return Duplicate(barcode: code, product: product, lotID: lotID, amount: amount, total: lot.quantity + amount)
    }

    private func resolve(_ code: Barcode) async {
        guard let inputs else {
            scanner.resume()
            return
        }
        let statuses = LotStatusEvaluator.statuses(for: inputs, profiles: services.profiles, on: today)
        var outcome = ScanResolution.resolve(code, products: inputs.products, statuses: statuses, lookup: nil)
        var lookedUp: LookedUpProduct?
        var guess: NameProfileGuesser.Guess?
        if case .lookingUp = outcome {
            lookingUp = code
            let result = await services.lookup.lookup(code)
            lookingUp = nil
            let lookup: ScanLookup
            switch result {
            case .found(let product):
                lookedUp = product
                guess = OpenFoodFacts.profileGuess(
                    product, categories: services.offCategories, names: services.nameProfiles,
                    profiles: services.profiles)
                lookup = .found(OpenFoodFacts.draft(
                    from: product, barcode: code, categories: services.offCategories,
                    names: services.nameProfiles, profiles: services.profiles))
            case .notFound: lookup = .notFound
            case .unavailable(let reason): lookup = .unavailable(reason)
            }
            outcome = ScanResolution.resolve(code, products: inputs.products, statuses: statuses, lookup: lookup)
        }
        func entry(_ draft: ProductDraft) -> NewProductEntry {
            NewProductEntry(
                draft: draft, amount: draft.unitKind == .count ? 1 : nil, lookedUp: lookedUp, guess: guess)
        }
        let subject: Card.Subject
        switch outcome {
        case .known(let product, _): subject = .known(product)
        case .found(let draft): subject = .new(entry(draft), found: true, reason: nil)
        case .notFound(let draft): subject = .new(entry(draft), found: false, reason: nil)
        case .lookupUnavailable(let draft, let reason): subject = .new(entry(draft), found: false, reason: reason)
        case .lookingUp:
            scanner.resume()
            return
        }
        var card = Card(barcode: code, subject: subject)
        if card.unitKind == .count, card.amount == nil { card.amount = 1 }
        self.card = card
    }

    // MARK: Card edits (Slice 5)

    func setCardName(_ name: String) {
        card?.modify { $0.setName(name, guesser: services.nameProfiles, profiles: services.profiles) }
    }

    func setCardCategory(_ category: SupplyCategory) {
        card?.modify { $0.setCategory(category, guesser: services.nameProfiles, profiles: services.profiles) }
    }

    func pickCardProfile(_ key: ShelfLifeProfileKey) {
        card?.modify { $0.pickProfile(key) }
    }

    func updateCardCalories(_ change: (inout CalorieEntry) -> Void) {
        card?.modify { $0.updateCalories(change) }
    }

    // MARK: Card actions

    func skip() {
        card = nil
        scanner.resume()
    }

    /// Saves the card's lot (and its new product, in one write) into the walk's location.
    func add() async {
        guard let card, let amount = card.amount, amount > 0 else { return }
        let product: Product
        let isNew: Bool
        do {
            switch card.subject {
            case .known(let existing):
                product = existing
                isNew = false
            case .new(let entry, _, _):
                product = try entry.draft.product()
                isNew = true
            }
            let lot = Lot(
                productID: product.id, quantity: amount, acquiredDate: today, printedDate: card.printed.date,
                noPrintedDate: card.printed.isNoPrintedDate, locationID: walk.locationID)
            if isNew {
                try await services.lots.save(lot, newProduct: product)
            } else {
                try await services.lots.save(lot)
            }
            if card.printed.isNoPrintedDate, let months = card.estimateMonths {
                try await services.shelfLifeOverrides.save(ShelfLifeOverride(rotationMonths: months), for: lot.id)
            }
            let date = dateEntry(card)
            walk.record(isNew
                ? .createdProductAndLot(lot.id, product: product.id, amount: amount, date: date)
                : .createdLot(lot.id, product: product.id, amount: amount, date: date))
            productByBarcode[card.barcode] = product.id
            scanner.added(card.barcode)
            Preferences.setLastUsedLocation(walk.locationID, siteID: siteID)
            lastAdded = "\(product.name) · \(QuantityText.format(amount, product.baseUnit))"
            saves += 1
            self.card = nil
            scanner.resume()
        } catch let error as ProductDraftError {
            writeError = ProfileText.describe(error)
        } catch {
            writeError = ErrorText.describe(error)
        }
    }

    private func dateEntry(_ card: Card) -> PantryWalk.DateEntry {
        if profile(for: card)?.dateType == ShelfLifeDateType.none { return .notNeeded }
        switch card.printed {
        case .day: return .printed
        case .noPrintedDate: return .noPrintedDate
        case .unset: return .missing
        }
    }

    // MARK: Scanned again

    func addAnother() async {
        guard let duplicate else { return }
        do {
            try await services.lots.add(duplicate.lotID, amount: duplicate.amount)
            walk.record(.added(duplicate.lotID, product: duplicate.product.id, amount: duplicate.amount))
            lastAdded = "\(duplicate.product.name) · now \(QuantityText.format(duplicate.total, duplicate.product.baseUnit))"
            saves += 1
            self.duplicate = nil
            scanner.resume()
        } catch {
            writeError = ErrorText.describe(error)
        }
    }

    func doubleScan() {
        duplicate = nil
        scanner.resume()
    }

    /// "Different date": a new lot of the same product, starting at its date.
    func differentDate() {
        guard let duplicate else { return }
        self.duplicate = nil
        var card = Card(barcode: duplicate.barcode, subject: .known(duplicate.product))
        card.amount = duplicate.amount
        card.opensDateSheet = true
        self.card = card
    }

    // MARK: Undo

    /// Reverses the most recent Add: deletes the lot (and a product it created, if nothing else uses it) or takes
    /// back what was added to an existing lot.
    func undo() async {
        guard let plan = walk.undoLast() else { return }
        do {
            switch plan {
            case .deleteLot(let lot):
                try await services.lots.delete(lot)
            case .deleteLotAndProduct(let lot, let product):
                try await services.lots.delete(lot)
                try await services.products.deleteIfUnused(product)
            case .consume(let lot, let amount):
                try await services.lots.consume(lot, amount: amount)
            }
            lastAdded = nil
        } catch {
            writeError = ErrorText.describe(error)
        }
    }

    // MARK: Summary

    var runwayBefore: SiteRunway? {
        startInputs.map { RunwayCalculator.runway(for: $0, profiles: services.profiles, on: today) }
    }

    var runwayNow: SiteRunway? {
        inputs.map { RunwayCalculator.runway(for: $0, profiles: services.profiles, on: today) }
    }

    func product(_ id: ProductID) -> Product? { inputs?.products.first { $0.id == id } }
}
