import Foundation
import HearthstockCore
import Observation
import SwiftUI
import UIKit

/// The open database and the site the app shows. Replaced wholesale when a restore brings a new default site.
@MainActor @Observable
final class AppSession {
    let services: AppServices
    private(set) var siteID: SiteID

    init(services: AppServices, siteID: SiteID) {
        self.services = services
        self.siteID = siteID
    }

    /// After a restore: the restored database's oldest site (or a new "Home" if it had none).
    func reloadSite() async throws {
        siteID = try await services.sites.ensureDefaultSite().id
    }
}

/// "Today", computed once for the whole app and refreshed when the app becomes active and when the calendar day
/// changes, so a phone left open overnight moves lots from Good to Caution without a relaunch.
@MainActor @Observable
final class Today {
    private(set) var date: CalendarDate = .today()

    func refresh() {
        let now = CalendarDate.today()
        if now != date { date = now }
    }

    /// Runs until cancelled. The significant-time-change notification fires at midnight (and on time zone and
    /// clock changes) while the app runs; becoming active is handled by the scene phase.
    func watchForDayChanges() async {
        for await _ in NotificationCenter.default.notifications(named: UIApplication.significantTimeChangeNotification) {
            refresh()
        }
    }
}

/// Which tab is showing, and the Dashboard's drill-in into Inventory.
@MainActor @Observable
final class AppRouter {
    enum Tab: Hashable {
        case dashboard
        case inventory
        case settings
    }

    var tab: Tab = .dashboard
    /// Set by a Dashboard category card; Inventory applies it and shows a chip to clear it.
    var inventoryCategory: SupplyCategory?
    /// Bumped to ask Inventory to apply `inventoryCategory` even if it didn't change.
    var inventoryDrillIn = 0

    func showInventory(category: SupplyCategory?) {
        inventoryCategory = category
        inventoryDrillIn += 1
        tab = .inventory
    }
}

/// UI conveniences kept out of the database and the backup (Decision 8).
enum Preferences {
    private static var defaults: UserDefaults { .standard }

    static func lastUsedLocation(siteID: SiteID) -> LocationID? {
        defaults.string(forKey: "lastLocation.\(siteID)").flatMap(UUID.init(uuidString:)).map(LocationID.init(rawValue:))
    }

    static func setLastUsedLocation(_ id: LocationID, siteID: SiteID) {
        defaults.set(id.rawValue.uuidString, forKey: "lastLocation.\(siteID)")
    }

    static var lastExport: Date? {
        get { defaults.object(forKey: "lastExport") as? Date }
        set { defaults.set(newValue, forKey: "lastExport") }
    }
}
