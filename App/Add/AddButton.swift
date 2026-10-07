import SwiftUI

/// The "+" toolbar button on Dashboard and Inventory (Decision 2), presenting the Add sheet.
struct AddButtonModifier: ViewModifier {
    @State private var adding = false

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Add item", systemImage: "plus") { adding = true }
                }
            }
            .sheet(isPresented: $adding) { AddLotSheet() }
    }
}

extension View {
    func addItemButton() -> some View { modifier(AddButtonModifier()) }
}
