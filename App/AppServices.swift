import Foundation
import HearthstockCore
import HearthstockLookup
import HearthstockStore
import SwiftUI

/// Everything the screens talk to: repository protocols, not their GRDB implementations. The only app file that
/// imports HearthstockStore or HearthstockLookup.
struct AppServices: Sendable {
    let sites: any SiteRepository
    let people: any PersonRepository
    let locations: any LocationRepository
    let products: any ProductRepository
    let lots: any LotRepository
    let kits: any KitRepository
    let shelfLifeOverrides: any ShelfLifeOverrideRepository
    let runwayInputs: any RunwayInputsLoader
    let backup: any BackupService
    /// Barcode lookups, cached on the phone (each barcode leaves it at most once) and honoring the Settings switch.
    let lookup: any ProductLookupService
    let lookupCache: any LookupCacheRepository
    let profiles: ShelfLifeProfileTable
    let offCategories: OFFCategoryMap
    /// Profile guesses from a product's name, when its categories say nothing (Slice 5).
    let nameProfiles: NameProfileGuesser

    init(
        database: AppDatabase, profiles: ShelfLifeProfileTable, offCategories: OFFCategoryMap,
        nameProfiles: NameProfileGuesser
    ) {
        sites = GRDBSiteRepository(database: database)
        people = GRDBPersonRepository(database: database)
        locations = GRDBLocationRepository(database: database)
        products = GRDBProductRepository(database: database)
        lots = GRDBLotRepository(database: database)
        kits = GRDBKitRepository(database: database)
        shelfLifeOverrides = GRDBShelfLifeOverrideRepository(database: database)
        runwayInputs = GRDBRunwayInputsLoader(database: database)
        backup = GRDBBackup(database: database)
        let cache = GRDBLookupCacheRepository(database: database)
        lookupCache = cache
        lookup = CachingProductLookup(
            online: OpenFoodFactsClient(userAgent: Self.userAgent),
            cache: cache,
            isEnabled: { Preferences.onlineLookupEnabled })
        self.profiles = profiles
        self.offCategories = offCategories
        self.nameProfiles = nameProfiles
    }

    /// "Hearthstock/0.1.0 (contact)", from the version and the `OFF_CONTACT` build setting in project.yml.
    static var userAgent: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "0"
        let contact = info["OFFContact"] as? String ?? ""
        return contact.isEmpty ? "Hearthstock/\(version)" : "Hearthstock/\(version) (\(contact))"
    }

    /// Opens the on-disk database (running every migration), loads the bundled shelf-life table and makes
    /// sure the default site exists.
    static func start() async throws -> (services: AppServices, site: Site) {
        let (database, profiles, offCategories, nameProfiles) = try await Task.detached {
            // The category map and the name keywords only improve profile guesses; without them the app still opens.
            (try AppDatabase.onDisk(), try ShelfLifeProfileTable.bundledDefaults(),
             (try? OFFCategoryMap.bundled()) ?? .empty, (try? NameProfileGuesser.bundled()) ?? .empty)
        }.value
        let services = AppServices(
            database: database, profiles: profiles, offCategories: offCategories, nameProfiles: nameProfiles)
        let site = try await services.sites.ensureDefaultSite()
        return (services, site)
    }
}


