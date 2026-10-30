import HearthstockCore
import SwiftUI
import VisionKit

/// Live Text over the camera: reads the text in view and proposes printed dates from it (Slice 4 Task 13). Nothing is
/// saved here; picking a date fills the date sheet, and Done there confirms it.
struct DateTextScannerSheet: View {
    let onPick: (DateCandidate) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var candidates: [DateCandidate] = []
    @State private var access = CameraAccess.current

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Color.hsCameraBg.ignoresSafeArea()
                if access == .ready {
                    DateTextScannerView { text in
                        let found = PrintedDateParser.candidates(in: text)
                        if !found.isEmpty { candidates = found }
                    }
                    .ignoresSafeArea()
                } else {
                    Text(access == .denied
                        ? "The camera is off for Hearthstock. Turn it on in iOS Settings, or pick the date by hand."
                        : "Reading dates needs the camera, which isn't available here. Pick the date by hand.")
                        .foregroundStyle(Color.hsCameraInk2)
                        .multilineTextAlignment(.center)
                        .padding(24)
                        .frame(maxHeight: .infinity)
                }
                picks
            }
            .navigationTitle("Scan the date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .toolbarBackground(Color.hsCameraBg, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .task {
            if access == .notDetermined { access = await CameraAccess.request() }
        }
    }

    @ViewBuilder
    private var picks: some View {
        VStack(spacing: 10) {
            if let best = candidates.first {
                Button { pick(best) } label: {
                    VStack(spacing: 4) {
                        Text("Use this date").font(.caption.weight(.semibold)).opacity(0.8)
                        Text(label(best)).font(.title3.bold())
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(CameraPillStyle(prominent: true))
                if candidates.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(candidates.dropFirst(), id: \.self) { candidate in
                                Button(label(candidate)) { pick(candidate) }
                                    .buttonStyle(CameraPillStyle())
                            }
                        }
                    }
                }
            } else if access == .ready {
                Text("Point at the printed date: BEST BY, USE BY or EXP.")
                    .font(.subheadline)
                    .foregroundStyle(Color.hsCameraInk2)
                    .padding(.horizontal, 16).frame(minHeight: 44)
                    .background(Color.hsCameraControl, in: Capsule())
            }
        }
        .padding(16)
        .foregroundStyle(Color.hsCameraInk)
    }

    private func label(_ candidate: DateCandidate) -> String {
        let type = candidate.dateType.map { "\($0.label) " } ?? ""
        return type + (candidate.precision == .month ? candidate.date.monthYear : candidate.date.medium)
    }

    private func pick(_ candidate: DateCandidate) {
        onPick(candidate)
        dismiss()
    }
}

/// VisionKit's live text recognizer. Reports all the text in view, one line per recognized item, on each update.
private struct DateTextScannerView: UIViewControllerRepresentable {
    var onText: @MainActor (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.text()],
            qualityLevel: .accurate,
            recognizesMultipleItems: true,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        context.coordinator.onText = onText
        if !scanner.isScanning { try? scanner.startScanning() }
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onText: onText) }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onText: @MainActor (String) -> Void

        init(onText: @escaping @MainActor (String) -> Void) {
            self.onText = onText
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            report(allItems)
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didUpdate updatedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            report(allItems)
        }

        private func report(_ items: [RecognizedItem]) {
            let lines = items.compactMap { item -> String? in
                if case .text(let text) = item { return text.transcript }
                return nil
            }
            onText(lines.joined(separator: "\n"))
        }
    }
}
