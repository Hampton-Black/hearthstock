import SwiftUI

/// The "+" toolbar button on Dashboard and Inventory (Slice 4 Decision 14): opens Add · scan full screen, with
/// "Type it in" one tap away. Inventory adds the design's Scan button beside it, opening the same screen.
struct AddButtonModifier: ViewModifier {
    var showsScan = false
    @State private var adding = false

    func body(content: Content) -> some View {
        content
            .toolbar {
                if showsScan {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Scan", systemImage: "barcode.viewfinder") { adding = true }
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Add item", systemImage: "plus") { adding = true }
                }
            }
            .fullScreenCover(isPresented: $adding) { AddScanView() }
    }
}

extension View {
    func addItemButton(showsScan: Bool = false) -> some View { modifier(AddButtonModifier(showsScan: showsScan)) }
}
