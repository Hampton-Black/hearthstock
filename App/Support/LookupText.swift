import Foundation
import HearthstockCore

/// What a barcode lookup's answer says to a person.
enum LookupText {
    /// "Couldn't look it up right now", and why.
    static func unavailable(_ reason: LookupUnavailableReason) -> String {
        switch reason {
        case .offline: "Couldn't look it up right now: no internet connection."
        case .timedOut: "Couldn't look it up right now: Open Food Facts didn't answer in time."
        case .rateLimited: "Couldn't look it up right now: too many lookups in the last minute. Try again shortly."
        case .serverError: "Couldn't look it up right now: Open Food Facts had a problem."
        case .switchedOff: "Online lookup is off. Turn it on in Settings → Online lookup."
        }
    }

    /// What "Look up online" filled in, in the order the form shows them.
    static func filled(_ fields: Set<ProductDraft.FilledField>) -> String {
        guard !fields.isEmpty else { return "Nothing new: Open Food Facts doesn't have more for this barcode." }
        let names = ProductDraft.FilledField.allCases.filter(fields.contains).map { field -> String in
            switch field {
            case .name: "the name"
            case .calories: "calories"
            case .water: "drinking water"
            }
        }
        return "Filled in \(ListFormatter.localizedString(byJoining: names)) from Open Food Facts. Check them before saving."
    }
}
