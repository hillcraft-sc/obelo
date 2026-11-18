import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Settings ▸ Shortcuts: keys that let the iOS Shortcuts app send captures to your account
struct ShortcutsPane: View {
    @Environment(AppState.self) private var app
    @Environment(\.theme) private var theme
    @Bindable var hub: SettingsHub
    @State private var revoking: ApiTokenItem?

    private var tokens: ApiTokensStore { hub.tokens }

    private func when(_ date: Date?) -> String {
        guard let date else { return "never" }
        return SettingsFormat.when(date, hour12: app.hour12, timezone: hub.settings.account.timezone)
    }

    var body: some View {
        SettingsPage(notice: $hub.tokens.notice) {
            if let fresh = tokens.fresh, let token = fresh.token {
                KitCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Save this token now. It will not be shown again.").font(.system(size: 14, weight: .semibold)).foregroundStyle(theme.amber400)
                        Text("Token label: \(fresh.label)").font(.system(size: 12)).foregroundStyle(theme.textMuted)
                        HStack(spacing: 10) {
                            Text(token).font(.system(size: 12, design: .monospaced)).foregroundStyle(theme.text200).textSelection(.enabled)
                                .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                            Button("Copy") {
                                NSPasteboard.general.clearContents(); NSPasteboard.general.setString(token, forType: .string)
                                hub.tokens.notice = SettingsNotice(text: "Token copied", isError: false)
                            }.buttonStyle(KitButtonStyle(.secondary, small: true))
                        }
                        Text("Treat this like a password. Anyone with this token can add items to your account.").font(.system(size: 12)).foregroundStyle(theme.textMuted)
                        Button("Done") { hub.tokens.dismissFresh() }.buttonStyle(KitButtonStyle(.secondary, small: true))
                    }
                    .padding(16)
                }
            }
            SettingsCard(title: "API tokens", detail: "Used by iOS Shortcuts to send captures to your account.") {
                if tokens.loaded && tokens.tokens.isEmpty {
                    Text("No tokens yet. Create one below to use in your Shortcut.").font(.system(size: 14)).italic().foregroundStyle(theme.textMuted)
                }
                VStack(spacing: 0) {
                    ForEach(tokens.tokens) { t in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(t.label).font(.system(size: 14)).foregroundStyle(theme.text100)
                                Text("Created \(when(t.createdAt)) · last used \(when(t.lastUsed))").font(.system(size: 12)).foregroundStyle(theme.textMuted)
                            }
                            Spacer()
                            Button("Revoke") { revoking = t }.buttonStyle(KitButtonStyle(.danger, small: true))
                        }
                        .padding(.vertical, 8)
                        .overlay(alignment: .bottom) { if t.id != tokens.tokens.last?.id { KitDivider() } }
                    }
                }
                HStack(spacing: 10) {
                    KitTextField(placeholder: "Token label (e.g. iPhone Shortcut)", text: $hub.tokens.label, onSubmit: create)
                    Button("Create token", action: create).buttonStyle(KitButtonStyle(.primary))
                }
            }
            SettingsCard(title: "Capture from iOS Shortcuts") {
                ForEach(ApiTokensStore.howTo(server: APIClient.shared.serverURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))), id: \.self) { line in
                    Text(line).font(.system(size: 13)).foregroundStyle(theme.text400).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .task { await hub.tokens.load(); if hub.settings.data == nil { await hub.settings.load() } }
        .kitConfirm(ApiTokensStore.revokeQuestion, item: $revoking, confirmLabel: "Revoke", destructive: true) { t in
            Task { await hub.tokens.revoke(t) }
        }
    }

    private func create() { Task { await hub.tokens.create() } }
}

/// Settings ▸ Data: export your data, import from other tools or a previous export
struct DataPane: View {
    @Environment(AppState.self) private var app
    @Environment(\.theme) private var theme
    @Bindable var hub: SettingsHub

    private func today() -> String { Fmt.ymd(.now) }

    var body: some View {
        SettingsPage(notice: $hub.data.notice) {
            SettingsCard(title: "Export your data", detail: "Your data belongs to you. Download it anytime in open formats.") {
                ForEach(Array(ExportKind.all.enumerated()), id: \.element.id) { i, kind in
                    if i > 0 { KitDivider() }
                    KitSettingRow(title: kind.title, detail: kind.detail) {
                        Button {
                            Task {
                                guard let file = await hub.data.export(kind, on: today()) else { return }
                                KitSavePanel.save(file.data, as: file.filename) { message in
                                    if let message { hub.data.notice = SettingsNotice(text: message, isError: !message.hasPrefix("Saved")) }
                                }
                            }
                        } label: {
                            if hub.data.busy == kind.name { ProgressView().controlSize(.small) } else { Label("Export", systemImage: "square.and.arrow.up") }
                        }
                        .buttonStyle(KitButtonStyle(.secondary)).disabled(hub.data.busy != nil)
                    }
                }
            }
            SettingsCard(title: "Import data", detail: "Migrate from other tools or restore a previous export.") {
                ForEach(Array(ImportKind.allCases.enumerated()), id: \.element.id) { i, kind in
                    if i > 0 { KitDivider() }
                    KitSettingRow(title: kind.title, detail: kind.detail) {
                        KitFileButton(title: "Import…", systemImage: "square.and.arrow.down", types: Self.types(kind),
                                      allowsMultiple: kind.allowsSeveralFiles, isBusy: hub.data.busy == kind.rawValue) { urls in
                            Task {
                                let picked: [(name: String, data: Data)] = urls.compactMap { url in
                                    let scoped = url.startAccessingSecurityScopedResource()
                                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                                    return (try? Data(contentsOf: url)).map { (url.lastPathComponent, $0) }
                                }
                                if await hub.data.importFiles(kind, picked) { app.dataChanged() }
                            }
                        }
                    }
                }
            }
        }
    }

    private static func types(_ kind: ImportKind) -> [UTType] {
        switch kind {
        case .notes: [UTType(filenameExtension: "md") ?? .plainText, .plainText]
        case .tasks: [.commaSeparatedText]
        case .json: [.json]
        }
    }
}

enum SettingsFormat {
    /// "Nov 14, 3:20 PM" in the person's time zone and 12 or 24-hour choice
    static func when(_ date: Date, hour12: Bool, timezone: String) -> String {
        let f = DateFormatter()
        f.timeZone = TimeZone(identifier: timezone) ?? .current
        f.dateFormat = hour12 ? "MMM d, h:mm a" : "MMM d, HH:mm"
        return f.string(from: date)
    }
}
