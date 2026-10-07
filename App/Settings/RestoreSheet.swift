import HearthstockCore
import SwiftUI

/// What a backup file holds, what it will replace, and the restore itself (Decision 4: erase and import).
struct RestoreSheet: View {
    let url: URL
    let siteName: String

    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var phase: Phase = .reading
    @State private var current: BackupSummary?
    @State private var confirming = false
    @State private var restoring = false
    @State private var sharing: ShareItem?
    @State private var writeError: String?

    private enum Phase {
        case reading
        case ready(Data, BackupSummary)
        case unreadable(String)
    }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .reading:
                    ProgressView()
                case .unreadable(let message):
                    ContentUnavailableView {
                        Label("Can't restore this file", systemImage: "doc.questionmark")
                    } description: {
                        Text(message)
                    } actions: {
                        Text("Nothing was changed.").font(.footnote)
                    }
                case .ready(let data, let summary):
                    ready(data: data, summary: summary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.hsBg)
            .navigationTitle("Restore backup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .task { await read() }
        .interactiveDismissDisabled(restoring)
        .sheet(item: $sharing) { item in
            ShareSheet(url: item.url) { completed in
                if completed { Preferences.lastExport = Date() }
            }
        }
        .errorAlert($writeError, title: "Couldn't restore")
    }

    private func ready(data: Data, summary: BackupSummary) -> some View {
        VStack(spacing: 16) {
            List {
                Section {
                    HStack(spacing: 12) {
                        IconTile(symbol: "doc.text")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(url.lastPathComponent).font(.headline).lineLimit(2)
                            if let exportedAt = summary.exportedAt {
                                Text("Exported \(exportedAt.formatted(date: .abbreviated, time: .omitted))")
                                    .font(.subheadline).foregroundStyle(Color.hsInk2)
                            }
                        }
                    }
                    .listRowBackground(Color.clear)
                }
                Section("In this file") {
                    LabeledContent("Sites", value: summary.siteNames.joined(separator: ", "))
                    LabeledContent("Lots", value: "\(summary.lots)")
                    LabeledContent("Products", value: "\(summary.products)")
                    LabeledContent("Locations · people", value: "\(summary.locations) · \(summary.people)")
                }
                if let current {
                    Section("Will be replaced") {
                        Text(replacedText(current, since: summary.exportedAt))
                            .font(.subheadline)
                            .foregroundStyle(Color.hsAmber)
                            .listRowBackground(Color.hsAmberBg)
                    }
                }
            }
            .hearthList()

            VStack(spacing: 12) {
                Button("Export current data first") { Task { await exportCurrent() } }
                    .buttonStyle(PrimaryButtonStyle())
                Button("Replace with this backup") { confirming = true }
                    .buttonStyle(PrimaryButtonStyle(role: .destructive))
                    .disabled(restoring)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .confirmationDialog(
            "Replace everything on this iPhone?", isPresented: $confirming, titleVisibility: .visible
        ) {
            Button("Replace with this backup", role: .destructive) { Task { await restore(data) } }
        } message: {
            Text("This can't be undone. Export your current data first if you might want it back.")
        }
    }

    private func replacedText(_ current: BackupSummary, since exportedAt: Date?) -> String {
        var text = "Everything on this iPhone: \(current.lots) lots, \(current.products) products, \(current.locations) locations and \(current.people) people."
        if let exportedAt {
            text += " Anything added since \(exportedAt.formatted(.dateTime.month(.abbreviated).day())) will be lost."
        }
        return text
    }

    private func read() async {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let summary = try await session.services.backup.summary(of: data)
            current = try await session.services.backup.currentSummary()
            phase = .ready(data, summary)
        } catch {
            phase = .unreadable(ErrorText.describe(error))
        }
    }

    private func exportCurrent() async {
        do {
            sharing = ShareItem(url: try await BackupFile.write(session.services.backup, siteName: siteName))
        } catch {
            writeError = ErrorText.describe(error)
        }
    }

    private func restore(_ data: Data) async {
        restoring = true
        defer { restoring = false }
        do {
            try await session.services.backup.restore(data)
            try await session.reloadSite()
            dismiss()
        } catch {
            writeError = ErrorText.describe(error)
        }
    }
}
