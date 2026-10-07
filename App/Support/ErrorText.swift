import Foundation
import HearthstockCore
import SwiftUI

/// What a failed write or subscription says to a person.
enum ErrorText {
    static func describe(_ error: any Error) -> String {
        if let error = error as? RepositoryError { return describe(error) }
        if let error = error as? UnitConversionError {
            switch error {
            case .incompatibleKinds(let from, let to): return "A \(from.title.lowercased()) amount can't be entered for a product measured by \(to.title.lowercased())."
            case .invalidVoltage: return "Battery capacity needs a voltage above zero."
            }
        }
        if let error = error as? LocalizedError, let description = error.errorDescription { return description }
        return String(describing: error)
    }

    static func describe(_ error: RepositoryError) -> String {
        switch error {
        case .siteNotFound: "This site no longer exists."
        case .locationNotFound: "That location no longer exists. Pick another one."
        case .lotNotFound: "That item no longer exists."
        case .productNotFound: "That product no longer exists."
        case .locationHasLots:
            "This location still holds items (used-up ones are kept for history). Move or delete them first."
        case .locationHasChildren: "Other locations are inside this one. Move or delete them first."
        case .locationHasKit: "This location is a kit. Turn off \"This is a kit\" first."
        case .invalidAmount: "Enter an amount greater than zero."
        case .lotArchived: "This item is already used up."
        case .insufficientQuantity(_, let available, _):
            "That's more than is left (\(Amount.text(available)) in the product's base unit)."
        case .invalidNoticeWindow: "The notice window must be at least one day."
        case .lotProductMismatch: "The item and its new product don't match. Pick the product again."
        case .unitKindLocked:
            "This product already has items stored in its unit, so how it's measured can't change. Make a new product instead."
        }
    }
}

extension View {
    /// Shows `message` as an alert while it's set; dismissing clears it.
    func errorAlert(_ message: Binding<String?>, title: String = "Couldn't save") -> some View {
        alert(
            title,
            isPresented: Binding(get: { message.wrappedValue != nil }, set: { if !$0 { message.wrappedValue = nil } }),
            presenting: message.wrappedValue
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { text in
            Text(text)
        }
    }
}
