import HearthstockCore
import HearthstockStore
import SwiftUI

/// Everything the screens talk to: repository protocols, not their GRDB implementations. The only app file that
/// imports HearthstockStore.
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
    let profiles: ShelfLifeProfileTable

    init(database: AppDatabase, profiles: ShelfLifeProfileTable) {
        sites = GRDBSiteRepository(database: database)
        people = GRDBPersonRepository(database: database)
        locations = GRDBLocationRepository(database: database)
        products = GRDBProductRepository(database: database)
        lots = GRDBLotRepository(database: database)
        kits = GRDBKitRepository(database: database)
        shelfLifeOverrides = GRDBShelfLifeOverrideRepository(database: database)
        runwayInputs = GRDBRunwayInputsLoader(database: database)
        backup = GRDBBackup(database: database)
        self.profiles = profiles
    }

    /// Opens the on-disk database (running every migration), loads the bundled shelf-life table and makes
    /// sure the default site exists.
    static func start() async throws -> (services: AppServices, site: Site) {
        let (database, profiles) = try await Task.detached {
            (try AppDatabase.onDisk(), try ShelfLifeProfileTable.bundledDefaults())
        }.value
        let services = AppServices(database: database, profiles: profiles)
        let site = try await services.sites.ensureDefaultSite()
        return (services, site)
    }
}


