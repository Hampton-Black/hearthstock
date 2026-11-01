import HearthstockCore
import SwiftUI

/// Every saved product at this site, including products with nothing left.
@MainActor @Observable
final class ProductsModel {
    var query = ""
    private(set) var rows: [ProductCatalogRow] = []
    private(set) var loaded = false
    var writeError: String?

    func load(_ services: AppServices, siteID: SiteID) async {
        do {
            let products = try await services.products.search(name: "")
            let lots = try await services.lots.list(siteID: siteID, includeArchived: true)
            rows = ProductCatalog.rows(products: products, lots: lots)
            loaded = true
        } catch {
            writeError = ErrorText.describe(error)
        }
    }

    var visible: [ProductCatalogRow] {
        ProductCatalog.rows(
            products: rows.map(\.product), lots: rows.flatMap { $0.currentLots + $0.usedUpLots }, query: query)
    }
}

/// Opened from Inventory: find any saved product, then edit or clean it up on its page.
struct ProductsView: View {
    @Environment(AppSession.self) private var session
    @State private var model = ProductsModel()

    var body: some View {
        @Bindable var model = model
        List {
            if model.loaded && model.visible.isEmpty {
                ContentUnavailableView(
                    model.rows.isEmpty ? "No products yet" : "No matches",
                    systemImage: model.rows.isEmpty ? "shippingbox" : "magnifyingglass")
                    .listRowBackground(Color.clear)
            }
            ForEach(model.visible) { row in
                NavigationLink {
                    ProductPage(productID: row.id)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.product.name).foregroundStyle(Color.hsInk)
                        Text("\(row.product.category.title) · \(ProductsText.counts(row))")
                            .font(.caption).foregroundStyle(Color.hsInk2)
                    }
                }
            }
        }
        .hearthList()
        .searchable(text: $model.query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search products")
        .navigationTitle("Products")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { Task { await model.load(session.services, siteID: session.siteID) } }
        .errorAlert($model.writeError)
    }
}

/// One product: what's saved about it, its lots, Edit, and Delete once no lot is left.
struct ProductPage: View {
    let productID: ProductID

    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var model = ProductsModel()
    @State private var editing: Product?
    @State private var confirmingDelete = false

    private var row: ProductCatalogRow? { model.rows.first { $0.id == productID } }

    var body: some View {
        @Bindable var model = model
        Group {
            if let row {
                content(row)
            } else if model.loaded {
                ContentUnavailableView("This product was deleted", systemImage: "shippingbox")
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.hsBg)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let row {
                ToolbarItem(placement: .primaryAction) { Button("Edit") { editing = row.product } }
            }
        }
        .onAppear { reload() }
        .sheet(item: $editing, onDismiss: reload) { product in
            NavigationStack { ProductForm(editing: product) }
        }
        .confirmationDialog("Delete this product?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { delete() }
        } message: {
            Text("It's removed completely. You can add it again by scanning it.")
        }
        .errorAlert($model.writeError)
    }

    private func reload() {
        Task { await model.load(session.services, siteID: session.siteID) }
    }

    private func delete() {
        Task {
            do {
                if try await session.services.products.deleteIfUnused(productID) {
                    dismiss()
                } else {
                    model.writeError = "It still has lots, so it wasn't deleted."
                    await model.load(session.services, siteID: session.siteID)
                }
            } catch {
                model.writeError = ErrorText.describe(error)
            }
        }
    }

    private func content(_ row: ProductCatalogRow) -> some View {
        let product = row.product
        return List {
            Section {
                Text(product.name).font(.headline).foregroundStyle(Color.hsInk)
                LabeledContent("Category", value: product.category.title)
                LabeledContent("Measured in", value: product.unitKind.baseUnit.symbol)
                if product.category == .food {
                    LabeledContent(
                        "Calories",
                        value: product.kcalPerBaseUnit.map { CalorieText.value($0, unitKind: product.unitKind) } ?? "None yet")
                }
                LabeledContent("Shelf life", value: session.services.profiles[product.shelfLifeProfileKey]?.name ?? "")
                if let barcode = product.barcode { LabeledContent("Barcode", value: barcode) }
            }
            if !row.currentLots.isEmpty {
                Section("In your inventory") {
                    ForEach(row.currentLots) { lot in
                        NavigationLink {
                            LotDetailView(lotID: lot.id)
                        } label: {
                            Text("\(ProductsText.amount(lot, product)) · acquired \(lot.acquiredDate.medium)")
                        }
                    }
                }
            }
            if !row.usedUpLots.isEmpty {
                Section("Used up") {
                    ForEach(row.usedUpLots) { lot in
                        NavigationLink {
                            UsedUpLotView(lot: lot)
                        } label: {
                            Text("Acquired \(lot.acquiredDate.medium)")
                        }
                    }
                }
            }
            Section {
                Button("Delete product", systemImage: "trash", role: .destructive) { confirmingDelete = true }
                    .disabled(!row.canDelete)
            } footer: {
                Text(row.canDelete
                    ? "No lots are left, so this removes it completely."
                    : "\(row.lotCount == 1 ? "Delete its lot" : "Delete its \(row.lotCount) lots") first, used up ones included.")
            }
        }
        .hearthList()
    }
}

/// A used-up lot from the history: read-only, with Delete for entry mistakes.
struct UsedUpLotView: View {
    let lot: Lot

    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingDelete = false
    @State private var writeError: String?

    var body: some View {
        List {
            Section {
                LabeledContent("Acquired", value: lot.acquiredDate.medium)
                if let printed = lot.printedDate { LabeledContent("Printed date", value: printed.medium) }
                if let notes = lot.notes { LabeledContent("Notes", value: notes) }
            } footer: {
                Text("Used up, so it's not in your inventory or runway.")
            }
            Section {
                Button("Delete lot", systemImage: "trash", role: .destructive) { confirmingDelete = true }
            } footer: {
                Text("Delete is for entry mistakes and removes it from your history.")
            }
        }
        .hearthList()
        .navigationTitle("Used up")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Delete this item?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                Task {
                    do {
                        try await session.services.lots.delete(lot.id)
                        dismiss()
                    } catch {
                        writeError = ErrorText.describe(error)
                    }
                }
            }
        } message: {
            Text("For entry mistakes: it's removed completely.")
        }
        .errorAlert($writeError)
    }
}

enum ProductsText {
    static func lots(_ count: Int) -> String { count == 1 ? "1 lot" : "\(count) lots" }

    /// "1 item", "3 items", "25 lb".
    static func amount(_ lot: Lot, _ product: Product) -> String {
        if product.unitKind == .count { return lot.quantity == 1 ? "1 item" : "\(Amount.text(lot.quantity)) items" }
        return "\(Amount.text(lot.quantity)) \(product.unitKind.baseUnit.symbol)"
    }

    /// "2 lots · 1 used up", or "No lots".
    static func counts(_ row: ProductCatalogRow) -> String {
        if row.lotCount == 0 { return "No lots" }
        var parts: [String] = []
        if !row.currentLots.isEmpty { parts.append(lots(row.currentLots.count)) }
        if !row.usedUpLots.isEmpty { parts.append("\(row.usedUpLots.count) used up") }
        return parts.joined(separator: " · ")
    }
}
