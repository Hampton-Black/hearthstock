import HearthstockCore
import SwiftUI
import VisionKit

/// Live Text over the camera, read by a parser (Slice 4 Task 13, generalized in Slice 5 Task 6). Each update of the
/// text in view is folded into `Reading` by `read`; `picks` shows what it found over the camera and closes the sheet
/// when the person takes it. Nothing is saved here.
struct TextScannerSheet<Reading: Equatable, Picks: View>: View {
    let title: String
    /// What to point at, shown until there's something to pick.
    let hint: String
    /// Said in place of the camera when it's off ("…or pick the date by hand").
    let fallback: String
    /// The reading so far and the newest text in view → the new reading.
    let read: (Reading, String) -> Reading
    @ViewBuilder let picks: (Reading, _ close: @escaping () -> Void) -> Picks

    @Environment(\.dismiss) private var dismiss
    @State private var reading: Reading
    @State private var access = CameraAccess.current

    init(
        title: String, hint: String, fallback: String, initial: Reading,
        read: @escaping (Reading, String) -> Reading,
        @ViewBuilder picks: @escaping (Reading, _ close: @escaping () -> Void) -> Picks
    ) {
        self.title = title
        self.hint = hint
        self.fallback = fallback
        self.read = read
        self.picks = picks
        _reading = State(initialValue: initial)
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Color.hsCameraBg.ignoresSafeArea()
                if access == .ready {
                    LiveTextView { text in
                        let next = read(reading, text)
                        if next != reading { reading = next }
                    }
                    .ignoresSafeArea()
                } else {
                    Text(access == .denied
                        ? "The camera is off for Hearthstock. Turn it on in iOS Settings, or \(fallback)."
                        : "Reading text needs the camera, which isn't available here. You can \(fallback).")
                        .foregroundStyle(Color.hsCameraInk2)
                        .multilineTextAlignment(.center)
                        .padding(24)
                        .frame(maxHeight: .infinity)
                }
                VStack(spacing: 10) {
                    picks(reading) { dismiss() }
                    if access == .ready {
                        Text(hint)
                            .font(.subheadline)
                            .foregroundStyle(Color.hsCameraInk2)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16).frame(minHeight: 44)
                            .background(Color.hsCameraControl, in: Capsule())
                    }
                }
                .padding(16)
                .foregroundStyle(Color.hsCameraInk)
            }
            .navigationTitle(title)
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
}

/// Reads printed dates (Slice 4 Task 13). Picking a date fills the date sheet, and Done there confirms it.
struct DateTextScannerSheet: View {
    let onPick: (DateCandidate) -> Void

    var body: some View {
        TextScannerSheet(
            title: "Scan the date", hint: "Point at the printed date: BEST BY, USE BY or EXP.",
            fallback: "pick the date by hand", initial: [DateCandidate](),
            read: { old, text in
                let found = PrintedDateParser.candidates(in: text)
                return found.isEmpty ? old : found
            }
        ) { candidates, close in
            if let best = candidates.first {
                Button {
                    onPick(best)
                    close()
                } label: {
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
                                Button(label(candidate)) {
                                    onPick(candidate)
                                    close()
                                }
                                .buttonStyle(CameraPillStyle())
                            }
                        }
                    }
                }
            }
        }
    }

    private func label(_ candidate: DateCandidate) -> String {
        let type = candidate.dateType.map { "\($0.label) " } ?? ""
        return type + (candidate.precision == .month ? candidate.date.monthYear : candidate.date.medium)
    }
}

/// VisionKit's live text recognizer. Reports all the text in view, one line per recognized item, on each update.
struct LiveTextView: UIViewControllerRepresentable {
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
