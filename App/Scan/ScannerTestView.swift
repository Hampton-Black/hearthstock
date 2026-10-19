#if DEBUG
import HearthstockCore
import SwiftUI

/// Debug builds only: the scanner on its own, showing each normalized code, to check the camera, the torch and the
/// debouncer on a device before the Add flow uses them.
struct ScannerTestView: View {
    @State private var scanner = ScannerModel()
    @State private var last: ScanDebouncer.Event?
    @State private var count = 0

    var body: some View {
        CameraScreen(title: "Scanner test", scanner: scanner) {
            VStack(spacing: 12) {
                Text(scanner.inView.isEmpty ? "In view: nothing" : "In view: " + scanner.inView.map(\.rawValue).sorted().joined(separator: ", "))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Color.hsCameraInk2)
                if let last {
                    VStack(spacing: 4) {
                        Text(label(last)).font(.caption.weight(.semibold)).foregroundStyle(Color.hsCameraInk2)
                        Text(code(last).rawValue).font(.title2.monospacedDigit().bold())
                        Text("\(count) accepted").font(.caption).foregroundStyle(Color.hsCameraInk2)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(16)
                    .background(Color.hsCameraControl, in: RoundedRectangle(cornerRadius: 16))
                    HStack(spacing: 12) {
                        Button("Scan next") {
                            self.last = nil
                            scanner.resume()
                        }
                        .buttonStyle(CameraPillStyle())
                        Button("Mark added") {
                            scanner.added(code(last))
                            self.last = nil
                            scanner.resume()
                        }
                        .buttonStyle(CameraPillStyle(prominent: true))
                    }
                } else {
                    Text("Scan a barcode. Each accepted code shows here until you tap Scan next.")
                        .font(.subheadline)
                        .foregroundStyle(Color.hsCameraInk2)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .onAppear {
            scanner.onEvent = { event in
                last = event
                count += 1
            }
        }
    }

    private func code(_ event: ScanDebouncer.Event) -> Barcode {
        switch event {
        case .scan(let code), .repeat(let code): code
        }
    }

    private func label(_ event: ScanDebouncer.Event) -> String {
        switch event {
        case .scan: "SCANNED"
        case .repeat: "SCANNED AGAIN (already added)"
        }
    }
}
#endif
