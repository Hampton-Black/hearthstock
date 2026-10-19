import SwiftUI

/// Settings → Camera (Slice 4 Task 12): whether the scanner can use the camera, with a way to fix it.
struct CameraSection: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var access = CameraAccess.current

    var body: some View {
        Section {
            LabeledContent("Camera") {
                Text(status).foregroundStyle(access == .denied ? Color.hsAmber : Color.hsInk2)
            }
            switch access {
            case .denied:
                Button("Open iOS Settings") { CameraAccess.openSettings() }
            case .notDetermined:
                Button("Allow camera") { Task { access = await CameraAccess.request() } }
            case .ready, .unsupported:
                EmptyView()
            }
        } header: {
            Text("Scanning")
        } footer: {
            Text(footer)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { access = CameraAccess.current }
        }
    }

    private var status: String {
        switch access {
        case .ready: "Allowed"
        case .notDetermined: "Not asked yet"
        case .denied: "Off"
        case .unsupported: "Not available"
        }
    }

    private var footer: String {
        switch access {
        case .ready: "The camera reads barcodes and printed dates. You can also type barcodes."
        case .notDetermined: "The camera reads barcodes and printed dates. iOS asks the first time you scan."
        case .denied: "Scanning needs the camera. Turn it on for Hearthstock in iOS Settings, or type barcodes instead."
        case .unsupported: "This device can't scan with the camera. Type barcodes instead."
        }
    }
}
