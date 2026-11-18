import SwiftUI

// Capture — views/capture/index.ejs: type anything, the server's AI turns it into a task,
// reminder, note, journal, quote, list or bookmark, and you review the fields before saving.

struct CaptureView: View {
    @Environment(AppState.self) private var app
    @Environment(Toast.self) private var toast
    @Environment(\.theme) private var theme
    var prefill: String = ""

    @State private var raw = ""
    @State private var draft: CaptureDraft?
    @State private var processing = false
    @State private var saving = false
    @State private var error: String?
    @State private var saved: Route?
    @State private var started = false
    /// A type chosen before processing (nil = Auto, the AI decides)
    @State private var chosenType: String?

    private static let types = ["task", "reminder", "note", "journal", "quote", "list", "bookmark"]
    private static let labels = ["task": "Task", "reminder": "Reminder", "note": "Note", "journal": "Journal", "quote": "Quote", "list": "List", "bookmark": "Bookmark"]
    private static let icons = ["task": "✓", "reminder": "🔔", "note": "📝", "journal": "📖", "quote": "💬", "list": "📋", "bookmark": "🔖"]

    var body: some View {
        Page(maxWidth: 576) {
            PageHeader(title: "Capture", subtitle: app.me?.aiEnabled == false ? "Type anything and save it as a note." : "Type anything — AI will figure it out.", pageName: true)
            if app.me?.aiEnabled == false {
                Banner(kind: .warning, text: "AI isn't set up on this server, so Capture saves what you type as a note. The server admin can turn AI on by setting the AI_* variables in .env.")
            }
            if let error { Banner(kind: .error, text: error) }
            if let draft { review(draft) } else { input }
        }
        .navigationDestination(item: $saved) { RouteView(route: $0) }
        .onAppear {
            if !started { started = true; raw = prefill; if !prefill.isEmpty { process() } }
        }
    }

    // ── Input ────────────────────────────────────────────────────────────────

    private var input: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("", text: $raw, prompt: Text("remind me to call the dentist tuesday 3pm\ngrocery list: milk, eggs, bread, pasta\nbookmark reactjs.org — React docs").foregroundStyle(theme.placeholder), axis: .vertical)
                .lineLimit(4...10)
                .font(.system(size: 15))
                .foregroundStyle(theme.textPrimary)
                .padding(.horizontal, 16).padding(.vertical, 14)
                .background(theme.surface, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(theme.border2, lineWidth: 1))
            if app.me?.aiEnabled != false { typeRow }
            Button(action: process) {
                HStack(spacing: 8) {
                    if processing { ProgressView().tint(theme.onAccent).controlSize(.small); Text("Processing…") }
                    else { Text(app.me?.aiEnabled == false ? "Review note" : "Process with AI") }
                }
                .font(.system(size: 14, weight: .medium)).foregroundStyle(theme.onAccent)
                .frame(maxWidth: .infinity).padding(.vertical, 11)
                .background(theme.accent, in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(PressableStyle())
            .disabled(processing)
        }
    }

    // ── Review ───────────────────────────────────────────────────────────────

    private func review(_ d: CaptureDraft) -> some View {
        let s = d.suggestion
        let binding = { (kp: WritableKeyPath<CaptureSuggestion, String?>) in
            Binding<String>(get: { self.draft?.suggestion[keyPath: kp] ?? "" }, set: { self.draft?.suggestion[keyPath: kp] = $0 })
        }
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(Self.icons[s.type] ?? "📝")
                Text(Self.labels[s.type] ?? s.type).font(.system(size: 14, weight: .semibold)).foregroundStyle(theme.textPrimary)
                if s.confidence == "low" {
                    Badge(text: "Low confidence — check fields", fg: theme.amber400, bg: theme.amber900.opacity(0.5))
                } else if s.confidence == "medium" {
                    Badge(text: "Medium confidence", fg: theme.blue400, bg: Color(hex: "#1e3a8a").opacity(0.5))
                }
                Spacer()
            }
            .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 12)
            .overlay(alignment: .bottom) { RowDivider() }

            VStack(alignment: .leading, spacing: 16) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Self.types, id: \.self) { t in
                            Button { draft?.suggestion.type = t } label: {
                                Text("\(Self.icons[t]!) \(Self.labels[t]!)").font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(s.type == t ? theme.onAccent : theme.text400)
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(s.type == t ? theme.accent : theme.elevated, in: RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                if s.type == "bookmark" {
                    FormSection(label: "URL") { ThemedField(placeholder: "https://…", text: binding(\.url)).textInputAutocapitalization(.never) }
                }
                FormSection(label: "Title") { ThemedField(placeholder: "Title", text: binding(\.title)) }
                if s.type == "list" {
                    FormSection(label: "Items (one per line)") {
                        ThemedField(placeholder: "Milk\nEggs", text: Binding(
                            get: { (draft?.suggestion.items ?? []).joined(separator: "\n") },
                            set: { draft?.suggestion.items = $0.components(separatedBy: "\n") }
                        ), axis: .vertical).lineLimit(4...12)
                    }
                } else {
                    FormSection(label: s.type == "quote" ? "Quote" : s.type == "bookmark" ? "Description" : "Details") {
                        ThemedField(placeholder: "Optional", text: binding(\.content), axis: .vertical).lineLimit(3...10)
                    }
                }
                if s.type == "task" || s.type == "reminder" {
                    HStack(spacing: 12) {
                        FormSection(label: "Date") { OptionalDateField(ymd: Binding(get: { draft?.suggestion.dueDate }, set: { draft?.suggestion.dueDate = $0 })) }
                    }
                    FormSection(label: "Time") { OptionalTimeField(hhmm: Binding(get: { draft?.suggestion.dueTime }, set: { draft?.suggestion.dueTime = $0 })) }
                    FormSection(label: "Priority") {
                        SelectField(options: Fmt.priorities.map { ($0, Fmt.priorityLabel($0)) },
                                    selection: Binding(get: { draft?.suggestion.priority ?? "none" }, set: { draft?.suggestion.priority = $0 }))
                    }
                }
                if s.type == "quote" {
                    HStack(spacing: 12) {
                        FormSection(label: "Author") { ThemedField(placeholder: "Author", text: binding(\.author)) }
                        FormSection(label: "Source") { ThemedField(placeholder: "Source", text: binding(\.source)) }
                    }
                }
                if s.type != "list" && s.type != "reminder" {
                    FormSection(label: "Tags") {
                        TagsField(tags: Binding(get: { draft?.suggestion.tags ?? [] }, set: { draft?.suggestion.tags = $0 }))
                    }
                }
                HStack(spacing: 8) {
                    PrimaryButton(title: "Save \(Self.labels[s.type] ?? "")", systemImage: "checkmark", fullWidth: true, busy: saving) { confirm() }
                    SecondaryButton(title: "Discard") { reject() }
                }
                .padding(.top, 4)
            }
            .padding(20)
        }
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(theme.border2, lineWidth: 1))
    }

    /// Auto, or a type picked before processing, so the AI is told rather than left to guess
    private var typeRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Type").font(.system(size: 12, weight: .medium)).foregroundStyle(theme.text400)
            FlowLayout(spacing: 6) {
                ForEach([("auto", "Auto")] + Self.types.map { ($0, Self.labels[$0] ?? $0) }, id: \.0) { value, label in
                    let selected = (chosenType ?? "auto") == value
                    Button { chosenType = value == "auto" ? nil : value } label: {
                        Text(label).font(.system(size: 13, weight: .medium))
                            .foregroundStyle(selected ? theme.onAccent : theme.text400)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(selected ? theme.accent : theme.elevated, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            Text(chosenType == nil ? "Auto lets the AI decide." : "The AI fills in the details for a \(Self.labels[chosenType ?? ""]?.lowercased() ?? "note").")
                .font(.system(size: 12)).foregroundStyle(theme.textMuted)
        }
    }

    // ── Actions ──────────────────────────────────────────────────────────────

    private func process() {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !processing else { return }
        processing = true
        error = nil
        Task {
            defer { processing = false }
            do {
                var body: [String: Any] = ["raw": text]
                if let chosenType { body["type"] = chosenType }
                var d: CaptureDraft = try await APIClient.shared.post("/capture", body)
                // The server is told the choice, but an older server ignores it: the choice wins either way
                if let chosenType, d.suggestion.type != chosenType { d.suggestion.type = chosenType }
                withAnimation { draft = d }
            } catch { self.error = error.localizedDescription }
        }
    }

    private func confirm() {
        guard let d = draft else { return }
        let s = d.suggestion
        var body: [String: Any] = ["type": s.type]
        for (k, v) in [("title", s.title), ("content", s.content), ("dueDate", s.dueDate), ("dueTime", s.dueTime),
                       ("priority", s.priority), ("source", s.source), ("author", s.author), ("url", s.url)] {
            if let v { body[k] = v }
        }
        if let tags = s.tags { body["tags"] = tags }
        if let items = s.items { body["items"] = items.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty } }
        saving = true
        Task {
            defer { saving = false }
            do {
                struct R: Decodable { let type: String; let id: Int }
                let r: R = try await APIClient.shared.post("/capture/\(d.draftId)/confirm", body)
                toast.show("Saved \(Self.labels[r.type] ?? r.type)")
                app.dataChanged()
                draft = nil
                raw = ""
                chosenType = nil
                saved = switch r.type {
                case "task": .task(r.id)
                case "reminder": .reminder(r.id)
                case "list": .list(r.id)
                case "bookmark": .module("bookmarks")
                default: .note(r.id)
                }
            } catch { self.error = error.localizedDescription }
        }
    }

    private func reject() {
        guard let d = draft else { return }
        withAnimation { draft = nil }
        Task { try? await APIClient.shared.post("/capture/\(d.draftId)/reject") }
    }
}
