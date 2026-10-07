import HearthstockCore
import SwiftUI

/// Search existing products by name; most recently used first when the search is empty; "New product" always
/// first, prefilled with the search text.
struct ProductPicker: View {
    enum Choice {
        case existing(Product)
        case new(ProductDraft)
    }

    let onChoose: (Choice) -> Void

    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var products: [Product] = []
    @State private var loadError: String?
    @State private var creating: ProductDraft?

    var body: some View {
        List {
            Section {
                Button {
                    creating = ProductDraft(name: search.trimmingCharacters(in: .whitespacesAndNewlines))
                } label: {
                    HStack(spacing: 12) {
                        IconTile(symbol: "plus")
                        Text(search.isEmpty ? "New product" : "New product “\(search)”")
                            .font(.headline).foregroundStyle(Color.hsTint)
                    }
                }
            }
            if let loadError {
                Section { Text(loadError).foregroundStyle(Color.hsRed) }
            }
            if !products.isEmpty {
                Section(search.isEmpty ? "Recent" : "Matches") {
                    ForEach(products) { product in
                        Button {
                            onChoose(.existing(product))
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                IconTile(symbol: product.category.symbol, foreground: .hsInk2, background: .hsTrack)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(product.name).foregroundStyle(Color.hsInk)
                                    Text("\(product.category.title) · per \(product.unitKind.perUnit)")
                                        .font(.subheadline).foregroundStyle(Color.hsInk2)
                                }
                            }
                        }
                    }
                }
            }
        }
        .hearthList()
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search products")
        .navigationTitle("Choose product")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        }
        .task(id: search) { await load() }
        .navigationDestination(item: $creating) { draft in
            ProductForm(draft: draft) { finished in
                onChoose(.new(finished))
                dismiss()
            }
        }
    }

    private func load() async {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            products = query.isEmpty
                ? try await session.services.products.listByRecentUse()
                : try await session.services.products.search(name: query)
            loadError = nil
        } catch {
            loadError = ErrorText.describe(error)
        }
    }
}
