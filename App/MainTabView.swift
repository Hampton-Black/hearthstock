import HearthstockCore
import SwiftUI

/// Three tabs for Slice 3 (Decision 2): Runway, Inventory, Settings.
struct MainTabView: View {
    @State private var router = AppRouter()

    var body: some View {
        TabView(selection: $router.tab) {
            Tab("Runway", systemImage: "gauge.with.needle", value: AppRouter.Tab.dashboard) {
                DashboardView()
            }
            Tab("Inventory", systemImage: "shippingbox", value: AppRouter.Tab.inventory) {
                InventoryView()
            }
            Tab("Settings", systemImage: "gearshape", value: AppRouter.Tab.settings) {
                SettingsView()
            }
        }
        .environment(router)
    }
}
