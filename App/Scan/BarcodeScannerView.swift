import HearthstockCore
import SwiftUI
import Vision
import VisionKit

/// VisionKit's live barcode scanner. Reports every valid code in frame, already normalized, on each update; the
/// `ScanDebouncer` turns that stream into scans. Codes that fail normalization (a misread) are dropped here, so
/// nothing past this view sees a raw string.
struct BarcodeScannerView: UIViewControllerRepresentable {
    /// Called on the main actor with the codes in frame now, including an empty set when the last one leaves.
    var onSighting: @MainActor (Set<Barcode>) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        // UPC-A arrives as EAN-13 (or UPC-E); Barcode normalizes all of them to one form.
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.ean8, .ean13, .upce])],
            qualityLevel: .balanced,
            recognizesMultipleItems: true,
            isHighFrameRateTrackingEnabled: true,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        context.coordinator.onSighting = onSighting
        if !scanner.isScanning {
            try? scanner.startScanning()
        }
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onSighting: onSighting) }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onSighting: @MainActor (Set<Barcode>) -> Void

        init(onSighting: @escaping @MainActor (Set<Barcode>) -> Void) {
            self.onSighting = onSighting
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            report(allItems)
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didUpdate updatedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            report(allItems)
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didRemove removedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            report(allItems)
        }

        private func report(_ items: [RecognizedItem]) {
            onSighting(Set(items.compactMap(Self.barcode)))
        }

        private static func barcode(_ item: RecognizedItem) -> Barcode? {
            guard case .barcode(let found) = item, let payload = found.payloadStringValue else { return nil }
            let symbology: Barcode.Symbology? = switch found.observation.symbology {
            case .ean8: .ean8
            case .ean13: .ean13
            case .upce: .upcE
            default: nil
            }
            return try? Barcode(payload, symbology: symbology)
        }
    }
}
