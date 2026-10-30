import HearthstockCore
import SwiftUI

/// The products the runway couldn't count, each opening its product form. Missing calories (Focus next and the walk
/// summary) also says why each is missing and offers **Scan the label** (Slice 5 Task 8).
struct ProductFixList: View {
    let list: ProductList

    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var reasons: [ProductID: MissingCaloriesReason] = [:]
    @State private var lookedUp: [ProductID: LookedUpProduct] = [:]
    @State private var scanning: Product?
    /// A product with calories from its label, open in the product form for Save once the scanner has closed.
    @State private var pending: Product?
    @State private var filled: Product?

    var body: some View {
        NavigationStack {
            List(list.products) { product in
                VStack(alignment: .leading, spacing: 6) {
                    NavigationLink { ProductForm(editing: product) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(product.name)
                            if list.kind == .calories, let reason = reasons[product.id] {
                                Text(CalorieText.missing(reason)).font(.caption).foregroundStyle(Color.hsInk2)
                            } else if product.barcode != nil {
                                Label("Has a barcode: Look up online is inside", systemImage: "barcode.viewfinder")
                                    .font(.caption).foregroundStyle(Color.hsInk2)
                            }
                        }
                    }
                    if list.kind == .calories {
                        Button { scanning = product } label: {
                            Label("Scan the label", systemImage: "text.viewfinder").font(.subheadline.weight(.semibold))
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(Color.hsTint)
                    }
                }
            }
            .hearthList()
            .navigationTitle(list.kind == .calories ? "Missing calories" : "Missing water volume")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .sheet(item: $scanning, onDismiss: {
                filled = pending
                pending = nil
            }) { product in
                NutritionLabelScannerSheet { reading in
                    // An existing product keeps its unit kind (Decision 8 is for new products only).
                    CalorieFill.kcalPerBaseUnit(
                        lookedUp: lookedUp[product.id], unitKind: product.unitKind, label: reading
                    ).map { (kcal: $0.value, unitKind: product.unitKind) }
                } onUse: { reading in
                    guard let fill = CalorieFill.kcalPerBaseUnit(
                        lookedUp: lookedUp[product.id], unitKind: product.unitKind, label: reading)
                    else { return }
                    var withCalories = product
                    withCalories.kcalPerBaseUnit = fill.value
                    pending = withCalories
                }
            }
            .sheet(item: $filled) { product in
                NavigationStack { ProductForm(editing: product) }
            }
        }
        .task { await loadReasons() }
    }

    /// Why each is missing calories, from its saved lookup answer.
    private func loadReasons() async {
        guard list.kind == .calories else { return }
        for product in list.products {
            let barcode = product.barcode.flatMap { try? Barcode($0) }
            var cached: CachedLookup?
            if let barcode { cached = try? await session.services.lookupCache.get(barcode) }
            if case .found(let found)? = cached?.outcome { lookedUp[product.id] = found }
            reasons[product.id] = MissingCaloriesReason.reason(for: product, cached: cached)
        }
    }
}
