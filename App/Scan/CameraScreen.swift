import HearthstockCore
import SwiftUI

/// The always-dark camera screen shared by Add · scan and the pantry walk: close and torch buttons, the live
/// scanner behind a reticle, "Type a barcode" one tap away (Decision 13), and the caller's controls at the bottom.
///
/// Without a usable camera (simulator, older device, permission denied) the reticle is replaced by an explanation,
/// and typing still feeds the same path.
struct CameraScreen<Leading: View, Center: View, Trailing: View, Bottom: View>: View {
    let scanner: ScannerModel
    /// Hidden while a card covers the middle of the screen.
    var showsReticle = true
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var center: () -> Center
    /// After the torch button.
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var bottom: () -> Bottom

    @Environment(\.scenePhase) private var scenePhase
    @State private var torch = Torch()
    @State private var access = CameraAccess.current
    @State private var typing = false

    var body: some View {
        ZStack {
            Color.hsCameraBg.ignoresSafeArea()
            if access == .ready {
                BarcodeScannerView { codes in scanner.sighted(codes) }
                    .ignoresSafeArea()
            }
            VStack(spacing: 16) {
                topBar
                Spacer(minLength: 0)
                if showsReticle { middle }
                Spacer(minLength: 0)
                bottom()
            }
            .padding(16)
        }
        .foregroundStyle(Color.hsCameraInk)
        .environment(\.colorScheme, .dark)
        .sensoryFeedback(.impact(weight: .light), trigger: scanner.accepted)
        .sensoryFeedback(.warning, trigger: scanner.repeated)
        .sheet(isPresented: $typing) {
            TypeBarcodeSheet { code in scanner.typed(code) }
        }
        .task {
            if access == .notDetermined { access = await CameraAccess.request() }
        }
        .onChange(of: scenePhase) { _, phase in
            // Back from iOS Settings with the camera allowed.
            if phase == .active { access = CameraAccess.current }
            if phase != .active { torch.off() }
        }
        .onDisappear { torch.off() }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            leading()
            Spacer(minLength: 0)
            center()
            Spacer(minLength: 0)
            if access == .ready && torch.isAvailable {
                CameraButton(
                    symbol: torch.isOn ? "flashlight.on.fill" : "flashlight.off.fill",
                    label: torch.isOn ? "Turn off light" : "Turn on light"
                ) { torch.toggle() }
            } else if Trailing.self == EmptyView.self {
                Color.clear.frame(width: 44, height: 44)
            }
            trailing()
        }
    }

    @ViewBuilder
    private var middle: some View {
        VStack(spacing: 20) {
            switch access {
            case .ready:
                Reticle()
                    .frame(width: 300, height: 190)
                    .accessibilityHidden(true)
                Text("Point at a barcode").foregroundStyle(Color.hsCameraInk2)
            case .notDetermined:
                ProgressView()
            case .denied:
                CameraMessage(
                    symbol: "camera",
                    title: "Camera is off for Hearthstock",
                    text: "The camera reads barcodes and printed dates, so a shelf goes in one tap per item. You can turn it on in Settings, or type barcodes instead."
                ) {
                    Button("Open Settings") { CameraAccess.openSettings() }
                        .buttonStyle(CameraPillStyle(prominent: true))
                }
            case .unsupported:
                CameraMessage(
                    symbol: "barcode.viewfinder",
                    title: "Scanning isn't available here",
                    text: "This device can't scan barcodes with the camera. Type a barcode, or type the item in."
                ) { EmptyView() }
            }
            Button("Type a barcode", systemImage: "keyboard") { typing = true }
                .buttonStyle(CameraPillStyle(prominent: access != .ready))
        }
    }
}

extension CameraScreen where Leading == CameraCloseButton, Center == Text, Trailing == EmptyView {
    /// Close, a title and the torch across the top.
    init(title: String, scanner: ScannerModel, showsReticle: Bool = true, @ViewBuilder bottom: @escaping () -> Bottom) {
        self.init(
            scanner: scanner, showsReticle: showsReticle,
            leading: { CameraCloseButton() }, center: { Text(title).font(.headline) }, trailing: { EmptyView() },
            bottom: bottom)
    }
}

/// Closes the camera screen it's on.
struct CameraCloseButton: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        CameraButton(symbol: "xmark", label: "Close") { dismiss() }
    }
}

/// The four corner brackets and the scan line from the Add · scan artboard.
private struct Reticle: View {
    var body: some View {
        ZStack {
            Corners()
                .stroke(Color.hsCameraInk, style: StrokeStyle(lineWidth: 4, lineCap: .round))
            Rectangle()
                .fill(Color.hsCameraAccent)
                .frame(height: 2)
                .padding(.horizontal, 24)
        }
    }

    private struct Corners: Shape {
        func path(in rect: CGRect) -> Path {
            let length: CGFloat = 36, radius: CGFloat = 14
            var path = Path()
            for (corner, dx, dy) in [
                (CGPoint(x: rect.minX, y: rect.minY), 1.0, 1.0), (CGPoint(x: rect.maxX, y: rect.minY), -1.0, 1.0),
                (CGPoint(x: rect.minX, y: rect.maxY), 1.0, -1.0), (CGPoint(x: rect.maxX, y: rect.maxY), -1.0, -1.0),
            ] {
                path.move(to: CGPoint(x: corner.x, y: corner.y + dy * length))
                path.addLine(to: CGPoint(x: corner.x, y: corner.y + dy * radius))
                path.addQuadCurve(
                    to: CGPoint(x: corner.x + dx * radius, y: corner.y), control: corner)
                path.addLine(to: CGPoint(x: corner.x + dx * length, y: corner.y))
            }
            return path
        }
    }
}

private struct CameraMessage<Action: View>: View {
    let symbol: String
    let title: String
    let text: String
    @ViewBuilder var action: () -> Action

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol).font(.largeTitle).foregroundStyle(Color.hsCameraInk2)
            Text(title).font(.title3.bold()).multilineTextAlignment(.center)
            Text(text).foregroundStyle(Color.hsCameraInk2).multilineTextAlignment(.center)
            action()
        }
        .padding(.horizontal, 8)
    }
}

/// A round 44 pt button on the camera.
struct CameraButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .frame(width: 44, height: 44)
                .background(Color.hsCameraControl, in: Circle())
        }
        .accessibilityLabel(label)
    }
}

/// Capsule buttons on the camera: light and prominent, or a translucent fill.
struct CameraPillStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .padding(.horizontal, 20)
            .frame(minHeight: 48)
            .foregroundStyle(prominent ? Color.hsCameraBg : Color.hsCameraInk)
            .background(prominent ? Color.hsCameraInk : Color.hsCameraControl, in: Capsule())
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

/// Type a barcode by hand: validated by `Barcode`, so a code with a typo stays open with the reason.
struct TypeBarcodeSheet: View {
    let onCode: (Barcode) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var problem: String?
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Digits under the barcode", text: $text)
                        .keyboardType(.numberPad)
                        .font(.title3.monospacedDigit())
                        .focused($focused)
                        .onChange(of: text) { problem = nil }
                } footer: {
                    if let problem {
                        Label(problem, systemImage: "exclamationmark.circle").foregroundStyle(Color.hsRed)
                    } else {
                        Text("8, 12 or 13 digits. Spaces and dashes are fine.")
                    }
                }
            }
            .hearthList()
            .navigationTitle("Type a barcode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use") { submit() }
                        .disabled(text.allSatisfy { $0.isWhitespace || $0 == "-" })
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium])
    }

    private func submit() {
        do {
            let code = try Barcode(text)
            dismiss()
            onCode(code)
        } catch {
            problem = ProfileText.describe(error)
        }
    }
}
