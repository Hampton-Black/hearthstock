import AVFoundation
import HearthstockCore
import Observation
import SwiftUI
import UIKit
import VisionKit

/// Whether the scanner can run on this device right now.
enum CameraAccess: Equatable {
    /// No camera scanning here: an older device or the simulator. Typing is the only way in.
    case unsupported
    /// The permission prompt hasn't been shown yet.
    case notDetermined
    /// Denied or restricted (Screen Time, a device profile).
    case denied
    case ready

    @MainActor
    static var current: CameraAccess {
        guard DataScannerViewController.isSupported else { return .unsupported }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined: return .notDetermined
        case .authorized: return DataScannerViewController.isAvailable ? .ready : .denied
        default: return .denied
        }
    }

    /// Shows the system prompt (once per install) and returns the new state.
    @MainActor
    static func request() async -> CameraAccess {
        _ = await AVCaptureDevice.requestAccess(for: .video)
        return current
    }

    @MainActor
    static func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

/// The back camera's torch, for dark pantry corners. Hidden on devices without one.
@MainActor @Observable
final class Torch {
    private(set) var isOn = false
    let isAvailable = AVCaptureDevice.default(for: .video)?.hasTorch ?? false

    func toggle() { set(!isOn) }

    func off() {
        if isOn { set(false) }
    }

    private func set(_ on: Bool) {
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            device.torchMode = on ? .on : .off
            device.unlockForConfiguration()
            isOn = on
        } catch {
            isOn = false
        }
    }
}

/// The debouncer behind a scanner screen, plus the haptic triggers. Camera reads and typed codes take the same
/// path. `onEvent` gets each accepted scan or repeat; the screen calls `resume()` when it's ready for the next.
@MainActor @Observable
final class ScannerModel {
    private var debouncer = ScanDebouncer()
    /// Bumped on each accepted scan (a light tick) and each repeat (a warning), for `.sensoryFeedback`.
    private(set) var accepted = 0
    private(set) var repeated = 0
    var onEvent: (ScanDebouncer.Event) -> Void = { _ in }

    var isHolding: Bool { debouncer.isHolding }

    func sighted(_ codes: Set<Barcode>) {
        if let event = debouncer.sighted(codes, at: .now) { handle(event) }
    }

    func typed(_ code: Barcode) {
        if let event = debouncer.typed(code) { handle(event) }
    }

    func added(_ code: Barcode) { debouncer.added(code) }

    func resume() { debouncer.resume() }

    private func handle(_ event: ScanDebouncer.Event) {
        switch event {
        case .scan: accepted += 1
        case .repeat: repeated += 1
        }
        onEvent(event)
    }
}
