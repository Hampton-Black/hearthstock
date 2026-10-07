import HearthstockCore
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Backup state for Settings: export to the share sheet, or pick a file to restore (Task 11). The sheets hang off
/// the Settings screen, not the list rows, so scrolling can't tear them down.
@MainActor @Observable
final class BackupController {
    var sharing: ShareItem?
    var importing = false
    var restoring: RestoreRequest?
    var error: String?
    private(set) var lastExport = Preferences.lastExport

    func export(_ backup: any BackupService, siteName: String) async {
        do {
            sharing = ShareItem(url: try await BackupFile.write(backup, siteName: siteName))
        } catch {
            self.error = ErrorText.describe(error)
        }
    }

    func exported() {
        Preferences.lastExport = Date()
        lastExport = Preferences.lastExport
    }
}

/// The Backup rows.
struct BackupSection: View {
    let controller: BackupController
    let siteName: String
    @Environment(AppSession.self) private var session

    var body: some View {
        Section {
            Button {
                Task { await controller.export(session.services.backup, siteName: siteName) }
            } label: {
                HStack {
                    Label("Export backup", systemImage: "square.and.arrow.up")
                    Spacer()
                    if let lastExport = controller.lastExport {
                        Text("Last: \(lastExport.formatted(.dateTime.month(.abbreviated).day()))")
                            .font(.subheadline).foregroundStyle(Color.hsInk2)
                    }
                }
            }
            Button("Restore from backup…", systemImage: "square.and.arrow.down") { controller.importing = true }
        } header: {
            Text("Backup")
        } footer: {
            Text("Export saves one file with every lot, product, location and person. Restore replaces everything on this iPhone.")
        }
    }
}

extension View {
    /// The share sheet, file picker and restore sheet for `controller`.
    func backupPresentations(_ controller: BackupController, siteName: String) -> some View {
        @Bindable var controller = controller
        return sheet(item: $controller.sharing) { item in
            ShareSheet(url: item.url) { completed in
                if completed { controller.exported() }
            }
            .presentationDetents([.medium, .large])
        }
        .fileImporter(isPresented: $controller.importing, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url): controller.restoring = RestoreRequest(url: url)
            case .failure(let error): controller.error = ErrorText.describe(error)
            }
        }
        .sheet(item: $controller.restoring) { request in
            RestoreSheet(url: request.url, siteName: siteName)
        }
        .errorAlert($controller.error, title: "Couldn't export")
    }
}

struct ShareItem: Identifiable {
    let url: URL
    var id: URL { url }
}

struct RestoreRequest: Identifiable {
    let url: URL
    var id: URL { url }
}

enum BackupFile {
    /// Exports to a temporary file named for the site and today: "Hearthstock-Home-2026-10-06.json".
    static func write(_ backup: any BackupService, siteName: String) async throws -> URL {
        let data = try await backup.export()
        let safeName = siteName.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }.joined(separator: "-")
        let url = FileManager.default.temporaryDirectory
            .appending(path: "Hearthstock-\(safeName.isEmpty ? "Site" : safeName)-\(CalendarDate.today().iso).json")
        try data.write(to: url, options: .atomic)
        return url
    }
}

/// The system share sheet for one file.
struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    let completion: (Bool) -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        controller.completionWithItemsHandler = { _, completed, _, _ in completion(completed) }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
