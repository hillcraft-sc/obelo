import SwiftUI

// The share sheet ("Share → Obelo"): save what you're looking at as a bookmark, or send
// it to Capture to become a task, reminder, note, list… Uses the app's sign-in (App Group).
// Compiled into the share extension, and into the app (debug builds preview it).

struct SharedItem: Equatable {
    var url: String?
    var title: String?
    var text: String?
}

struct ShareView: View {
    @Environment(\.theme) private var theme
    let item: SharedItem
    let finish: (_ message: String?) -> Void

    enum Mode: String { case bookmark, capture }

    @State private var mode: Mode = .bookmark
    @State private var url = ""
    @State private var title = ""
    @State private var note = ""
    @State private var tags: [String] = []
    @State private var allTags: [String] = []
    @State private var raw = ""
    @State private var draft: CaptureDraft?
    @State private var busy = false
    @State private var error: String?
    @State private var signedOut = false
    @State private var loaded = false

    private var aiEnabled: Bool { AppGroup.aiEnabled }

    private static let labels = ["task": "Task", "reminder": "Reminder", "note": "Note", "journal": "Journal", "quote": "Quote", "list": "List", "bookmark": "Bookmark"]
    private static let icons = ["task": "✓", "reminder": "🔔", "note": "📝", "journal": "📖", "quote": "💬", "list": "📋", "bookmark": "🔖"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if signedOut {
                        Banner(kind: .warning, text: "You're signed out. Open the Obelo app and sign in, then share again.")
                    } else {
                        if aiEnabled {
                            Picker("Save as", selection: $mode) {
                                Text("Bookmark").tag(Mode.bookmark)
                                Text("Capture").tag(Mode.capture)
                            }
                            .pickerStyle(.segmented).labelsHidden()
                        }
                        if let error { Banner(kind: .error, text: error) }
                        if mode == .bookmark { bookmarkForm } else { captureForm }
                    }
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.immediately)
            .background(theme.page)
            .themedNavBar(theme, title: "Obelo")
            .keyboardDoneButton()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { finish(nil) }.foregroundStyle(theme.text400)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if busy { ProgressView() } else if !signedOut {
                        Button(primaryTitle, action: primary).fontWeight(.semibold).disabled(!canSubmit)
                    }
                }
            }
        }
        .task { await setUp() }
    }

    // ── Bookmark ─────────────────────────────────────────────────────────────

    private var bookmarkForm: some View {
        VStack(alignment: .leading, spacing: 16) {
            FormSection(label: "URL") {
                ThemedField(placeholder: "https://…", text: $url)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
            }
            FormSection(label: "Title") { ThemedField(placeholder: "Optional", text: $title) }
            FormSection(label: "Description") { ThemedField(placeholder: "Optional", text: $note, axis: .vertical).lineLimit(2...5) }
            FormSection(label: "Tags") { TagsField(tags: $tags, suggestions: allTags) }
        }
    }

    // ── Capture ──────────────────────────────────────────────────────────────

    @ViewBuilder private var captureForm: some View {
        if let d = draft {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text(Self.icons[d.suggestion.type] ?? "📝")
                    Text(Self.labels[d.suggestion.type] ?? d.suggestion.type)
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(theme.textPrimary)
                    if d.suggestion.confidence == "low" {
                        Badge(text: "Low confidence — check it", fg: theme.amber400, bg: theme.amber900.opacity(0.5))
                    }
                }
                Text(d.suggestion.title ?? "Untitled").font(.system(size: 16, weight: .medium)).foregroundStyle(theme.text100)
                let due = Fmt.due(d.suggestion.dueDate, d.suggestion.dueTime, hour12: true)
                if !due.isEmpty { Label(due, systemImage: "calendar").font(.system(size: 13)).foregroundStyle(theme.text400) }
                if let items = d.suggestion.items, !items.isEmpty {
                    Text(items.prefix(6).map { "• \($0)" }.joined(separator: "\n")).font(.system(size: 13)).foregroundStyle(theme.text400)
                }
                if let content = d.suggestion.content, !content.isEmpty {
                    Text(content).font(.system(size: 13)).foregroundStyle(theme.textMuted).lineLimit(4)
                }
                Text("Saving this as shown. To change any fields, use Capture in the app.")
                    .font(.system(size: 12)).foregroundStyle(theme.textMuted).padding(.top, 4)
                SecondaryButton(title: "Start over", systemImage: "arrow.uturn.backward") { reject() }.padding(.top, 4)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(theme.border2, lineWidth: 1))
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Type or edit anything — AI will figure out whether it's a task, reminder, note, list or bookmark.")
                    .font(.system(size: 12)).foregroundStyle(theme.textMuted)
                ThemedField(placeholder: "remind me to read this tomorrow", text: $raw, axis: .vertical).lineLimit(3...8)
            }
        }
    }

    // ── Actions ──────────────────────────────────────────────────────────────

    private var primaryTitle: String {
        mode == .bookmark ? "Save" : (draft == nil ? "Process" : "Save")
    }

    private var canSubmit: Bool {
        switch mode {
        case .bookmark: !url.trimmingCharacters(in: .whitespaces).isEmpty
        case .capture: draft != nil || !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func setUp() async {
        guard !loaded else { return }
        loaded = true
        url = item.url ?? (item.text.flatMap(Self.firstURL) ?? "")
        title = item.title ?? ""
        raw = [item.text, item.url].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
        if item.url == nil, item.text != nil, Self.firstURL(item.text ?? "") == nil, aiEnabled { mode = .capture }
        struct T: Decodable { let tags: [String] }
        do {
            let t: T = try await APIClient.shared.get("/tags")
            allTags = t.tags
        } catch APIError.unauthorized {
            signedOut = true
        } catch {}
    }

    private func primary() {
        error = nil
        busy = true
        Task {
            defer { busy = false }
            do {
                switch mode {
                case .bookmark:
                    try await APIClient.shared.post("/bookmarks", ["url": url, "title": title, "description": note, "tags": tags])
                    finish("Saved to Bookmarks")
                case .capture:
                    if let d = draft {
                        struct R: Decodable { let type: String; let id: Int }
                        let r: R = try await APIClient.shared.post("/capture/\(d.draftId)/confirm", [:])
                        finish("Saved \(Self.labels[r.type] ?? r.type)")
                    } else {
                        let d: CaptureDraft = try await APIClient.shared.post("/capture", ["raw": raw])
                        withAnimation { draft = d }
                    }
                }
            } catch APIError.unauthorized {
                signedOut = true
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func reject() {
        guard let d = draft else { return }
        withAnimation { draft = nil }
        Task { try? await APIClient.shared.post("/capture/\(d.draftId)/reject") }
    }

    static func firstURL(_ text: String) -> String? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let match = detector?.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
        return match?.url?.absoluteString
    }
}
