import SwiftUI

// Settings round two — the web's Notifications, Notes and Tags tabs.

// ── Notifications ────────────────────────────────────────────────────────────

struct NotificationsTab: View {
    @Environment(Toast.self) private var toast
    @Environment(\.theme) private var theme
    @Environment(AppState.self) private var app
    private var demo: Bool { app.me?.demo == true }
    @Environment(\.openURL) private var openURL

    @State private var s: NotificationSettings?
    @State private var saved: NotificationSettings?
    @State private var error: String?
    @State private var saving = false
    @State private var confirmNewTopic = false

    private static let typeInfo: [(key: String, label: String, desc: String, timed: Bool)] = [
        ("daily_digest", "Daily digest", "Today's calendar events and top tasks", true),
        ("slipping_tasks", "Slipping tasks", "Monday morning summary of overdue tasks", true),
        ("task_due", "Task & reminder alerts", "15 min before, at the due time, and when overdue — for any task or reminder with a set time", false),
    ]

    private var dirty: Bool {
        guard let s, let saved else { return false }
        return s.pushoverKey != saved.pushoverKey || s.pushoverEnabled != saved.pushoverEnabled || s.ntfyEnabled != saved.ntfyEnabled
            || s.notifEmail != saved.notifEmail || s.types != saved.types
    }

    var body: some View {
        Page(refresh: load) {
            if demo { Banner(kind: .warning, text: "Calendar accounts and notification channels aren't available on the demo. Run your own Obelo server to connect them.") }
            if let error { Banner(kind: .error, text: error) }
            if let binding = Binding($s) {
                channels(binding)
                types(binding)
                PrimaryButton(title: "Save notification settings", fullWidth: true, busy: saving) { save() }
                    .disabled(!dirty).opacity(dirty ? 1 : 0.5)
            } else if error == nil {
                ProgressView().frame(maxWidth: .infinity).padding(40)
            }
        }
        .disabled(demo)
        .task { if s == nil { await load() } }
        .confirmationDialog("Create a new ntfy topic?", isPresented: $confirmNewTopic, titleVisibility: .visible) {
            Button("New topic", role: .destructive) { newTopic() }
        } message: {
            Text("Your old topic stops getting notifications. Subscribe to the new one in the ntfy app.")
        }
    }

    // Delivery channels
    private func channels(_ s: Binding<NotificationSettings>) -> some View {
        Card {
            CardHeader(title: "Delivery channels")
            VStack(alignment: .leading, spacing: 18) {
                // Pushover
                VStack(alignment: .leading, spacing: 8) {
                    ToggleRow(title: "Pushover", subtitle: s.wrappedValue.pushoverAvailable ? "Paid app · paste your user key" : "Not set up on this server (PUSHOVER_APP_TOKEN)", isOn: s.pushoverEnabled)
                    if s.wrappedValue.pushoverEnabled {
                        ThemedField(placeholder: "Pushover user key", text: s.pushoverKey)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                    }
                }
                RowDivider()
                // ntfy
                VStack(alignment: .leading, spacing: 8) {
                    ToggleRow(title: "ntfy", subtitle: s.wrappedValue.ntfyAvailable ? "Free push app" : "Not set up on this server (NTFY_URL)", isOn: s.ntfyEnabled)
                        .disabled(!s.wrappedValue.ntfyAvailable && !s.wrappedValue.ntfyEnabled)
                    if s.wrappedValue.ntfyEnabled {
                        if s.wrappedValue.ntfyTopic.isEmpty {
                            Text("Save to get your personal topic and subscribe instructions.").font(.system(size: 12)).foregroundStyle(theme.textMuted)
                        } else {
                            VStack(alignment: .leading, spacing: 6) {
                                infoRow("Server", s.wrappedValue.ntfyServer)
                                infoRow("Topic", s.wrappedValue.ntfyTopic)
                                Text("In the ntfy app, tap + and subscribe to this topic on this server. Keep the topic private — anyone who knows it can read your notifications.")
                                    .font(.system(size: 12)).foregroundStyle(theme.textMuted)
                                FlowLayout(spacing: 8) {
                                    SecondaryButton(title: "Copy topic", systemImage: "doc.on.doc") {
                                        Clipboard.copy(s.wrappedValue.ntfyTopic)
                                        toast.show("Topic copied")
                                    }
                                    SecondaryButton(title: "Send test", systemImage: "paperplane") { test("test-ntfy") }
                                    SecondaryButton(title: "New topic", systemImage: "arrow.triangle.2.circlepath") { confirmNewTopic = true }
                                }
                            }
                            .padding(12)
                            .background(theme.elevated.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
                RowDivider()
                // Email
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Email").font(.system(size: 14, weight: .medium)).foregroundStyle(theme.text200)
                        Spacer()
                        if !s.wrappedValue.emailAvailable {
                            Text("Not set up on this server").font(.system(size: 12)).foregroundStyle(theme.textMuted)
                        }
                    }
                    ThemedField(placeholder: s.wrappedValue.accountEmail.isEmpty ? "you@example.com" : s.wrappedValue.accountEmail, text: s.notifEmail)
                        .keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Text("Leave blank to use your account email.").font(.system(size: 12)).foregroundStyle(theme.textMuted)
                    SecondaryButton(title: "Send test email", systemImage: "envelope") { test("test-email") }
                }
            }
            .padding(20)
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label).font(.system(size: 12)).foregroundStyle(theme.textMuted).frame(width: 46, alignment: .leading)
            Text(value).font(.system(size: 12, design: .monospaced)).foregroundStyle(theme.text200).textSelection(.enabled)
        }
    }

    // Notification types
    private func types(_ s: Binding<NotificationSettings>) -> some View {
        Card {
            CardHeader(title: "Notification types")
            Text("Reminders and routine alerts fire automatically at their scheduled times, to every push channel you've turned on above.")
                .font(.system(size: 12)).foregroundStyle(theme.textMuted)
                .padding(.horizontal, 20).padding(.top, 14)
            ForEach(Array(Self.typeInfo.enumerated()), id: \.offset) { i, info in
                if i > 0 { RowDivider().padding(.top, 4) }
                if let pref = Binding(s.types[info.key]) {
                    VStack(alignment: .leading, spacing: 10) {
                        ToggleRow(title: info.label, subtitle: info.desc, isOn: pref.enabled)
                        if pref.wrappedValue.enabled {
                            if info.timed {
                                HStack {
                                    Text("Send at").font(.system(size: 13)).foregroundStyle(theme.text400)
                                    Spacer()
                                    DatePicker("", selection: Binding(
                                        get: { Fmt.date(fromHHMM: pref.wrappedValue.sendTime) },
                                        set: { pref.wrappedValue.sendTime = Fmt.hhmm(from: $0) }
                                    ), displayedComponents: .hourAndMinute).labelsHidden()
                                }
                            }
                            HStack(spacing: 6) {
                                channelChip("Pushover", isOn: pref.channels.pushover)
                                channelChip("ntfy", isOn: pref.channels.ntfy)
                                channelChip("Email", isOn: pref.channels.email)
                            }
                        }
                    }
                    .padding(.horizontal, 20).padding(.vertical, 12)
                }
            }
        }
    }

    private func channelChip(_ label: String, isOn: Binding<Bool>) -> some View {
        Button { isOn.wrappedValue.toggle() } label: {
            HStack(spacing: 4) {
                Image(systemName: isOn.wrappedValue ? "checkmark.square.fill" : "square").font(.system(size: 12))
                Text(label).font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(isOn.wrappedValue ? theme.onAccent : theme.text400)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(isOn.wrappedValue ? theme.accent : theme.elevated, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn.wrappedValue ? .isSelected : [])
    }

    private func load() async {
        do {
            let r: NotificationSettings = try await APIClient.shared.get("/settings/notifications")
            s = r; saved = r; error = nil
        } catch { self.error = error.localizedDescription }
    }

    private func save() {
        guard let s, let body = try? JSONSerialization.jsonObject(with: JSONEncoder().encode(s)) as? [String: Any] else { return }
        saving = true
        Task {
            defer { saving = false }
            do {
                try await APIClient.shared.post("/settings/notifications", body, method: "PUT")
                toast.show("Notification settings saved")
                await load() // picks up a new ntfy topic
            } catch { toast.show(error.localizedDescription, error: true) }
        }
    }

    private func test(_ which: String) {
        if dirty { toast.show("Save your changes first", error: true); return }
        toast.run {
            struct R: Decodable { let message: String }
            let r: R = try await APIClient.shared.post("/settings/notifications/\(which)")
            toast.show(r.message)
        }
    }

    private func newTopic() {
        toast.run {
            struct R: Decodable { let ntfyTopic: String }
            let r: R = try await APIClient.shared.post("/settings/notifications/ntfy-topic")
            s?.ntfyTopic = r.ntfyTopic; saved?.ntfyTopic = r.ntfyTopic
            toast.show("New topic created — subscribe to it in the ntfy app")
        }
    }
}

// ── Notes ────────────────────────────────────────────────────────────────────

struct NotesSettingsTab: View {
    @Environment(AppState.self) private var app
    @Environment(Toast.self) private var toast
    @Environment(\.theme) private var theme

    struct Prefs: Decodable { var autosaveEnabled: Bool; var autosaveDuration: String; var hasPin: Bool; var notePaper: String? = nil }

    @State private var prefs: Prefs?
    @State private var currentPin = ""
    @State private var newPin = ""
    @State private var confirmPin = ""
    @State private var pinError: String?
    @State private var busy = false

    var body: some View {
        Page(refresh: load) {
            if let p = prefs {
                // Only offered when the server has the setting (an older server doesn't send it)
                if p.notePaper != nil {
                    Card {
                        CardHeader(title: "Handwriting paper")
                        VStack(alignment: .leading, spacing: 12) {
                            Text("The paper behind handwritten notes. The pen colours adjust to it, and drawings made on one paper read fine on the other.")
                                .font(.system(size: 12)).foregroundStyle(theme.textMuted)
                            SelectField(options: [("theme", "Match theme"), ("dark", "Dark"), ("white", "White")],
                                        selection: Binding(get: { p.notePaper ?? "theme" }, set: { setPaper($0) }))
                        }
                        .padding(20)
                    }
                }
                Card {
                    CardHeader(title: "Autosave")
                    VStack(alignment: .leading, spacing: 12) {
                        ToggleRow(title: "Autosave while editing", subtitle: "Applies to the web note editor", isOn: Binding(
                            get: { p.autosaveEnabled }, set: { prefs?.autosaveEnabled = $0; saveAutosave() }))
                        if p.autosaveEnabled {
                            SelectField(options: [("immediate", "Immediately"), ("2min", "Every 2 minutes"), ("5min", "Every 5 minutes")],
                                        selection: Binding(get: { p.autosaveDuration }, set: { prefs?.autosaveDuration = $0; saveAutosave() }))
                        }
                    }
                    .padding(20)
                }
                Card {
                    CardHeader(title: "Note lock PIN", badge: p.hasPin ? "set" : nil)
                    VStack(alignment: .leading, spacing: 12) {
                        Text(p.hasPin ? "Locked notes are opened with this PIN. To change it, enter the current one first."
                                      : "Set a 4–6 digit PIN to lock private notes. Locked notes are encrypted and need the PIN to read.")
                            .font(.system(size: 12)).foregroundStyle(theme.textMuted)
                        if let pinError { Banner(kind: .error, text: pinError) }
                        if p.hasPin { pinField("Current PIN", $currentPin) }
                        pinField(p.hasPin ? "New PIN" : "PIN", $newPin)
                        pinField("Confirm new PIN", $confirmPin)
                        HStack(spacing: 8) {
                            PrimaryButton(title: p.hasPin ? "Change PIN" : "Set PIN", busy: busy) { setPin(remove: false) }
                            if p.hasPin {
                                SecondaryButton(title: "Remove PIN", tint: theme.red400) { setPin(remove: true) }
                            }
                        }
                    }
                    .padding(20)
                }
            } else {
                ProgressView().frame(maxWidth: .infinity).padding(40)
            }
            NoteTemplatesCard()
        }
        .task { if prefs == nil { await load() } }
    }

    private func pinField(_ placeholder: String, _ text: Binding<String>) -> some View {
        SecureField("", text: text, prompt: Text(placeholder).foregroundStyle(theme.placeholder))
            .keyboardType(.numberPad)
            .textContentType(.oneTimeCode)
            .font(.system(size: 15)).foregroundStyle(theme.text100)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(theme.isDark ? theme.elevated : theme.surface, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.border2, lineWidth: 1))
            .onChange(of: text.wrappedValue) { _, v in
                let digits = String(v.filter(\.isNumber).prefix(6))
                if digits != v { text.wrappedValue = digits }
            }
    }

    private func load() async {
        prefs = try? await APIClient.shared.get("/settings/notes")
    }

    private func saveAutosave() {
        guard let p = prefs else { return }
        toast.run {
            var body: [String: Any] = ["autosaveEnabled": p.autosaveEnabled, "autosaveDuration": p.autosaveDuration]
            if let paper = p.notePaper { body["notePaper"] = paper }
            try await APIClient.shared.post("/settings/notes", body, method: "PUT")
        }
    }

    private func setPaper(_ paper: String) {
        prefs?.notePaper = paper
        app.me?.notePaper = paper // drawings on screen change at once
        saveAutosave()
    }

    private func setPin(remove: Bool) {
        pinError = nil
        busy = true
        Task {
            defer { busy = false }
            do {
                struct R: Decodable { let message: String }
                let body: [String: Any] = remove
                    ? ["action": "remove", "currentPin": currentPin]
                    : ["currentPin": currentPin, "newPin": newPin, "confirmPin": confirmPin]
                let r: R = try await APIClient.shared.post("/settings/note-pin", body)
                currentPin = ""; newPin = ""; confirmPin = ""
                toast.show(r.message)
                await load()
                try? await app.loadMe() // shows or hides "Lock" on notes
            } catch { pinError = error.localizedDescription }
        }
    }
}

// ── Tags ─────────────────────────────────────────────────────────────────────

struct TagsTab: View {
    @Environment(AppState.self) private var app
    @Environment(Toast.self) private var toast
    @Environment(\.theme) private var theme

    struct Tag: Decodable, Identifiable { let name: String; let count: Int; var id: String { name } }

    @State private var tags: [Tag]?
    @State private var newTag = ""
    @State private var renaming: Tag?
    @State private var renameText = ""
    @State private var deleting: Tag?

    var body: some View {
        Page(refresh: load) {
            HStack(spacing: 8) {
                ThemedField(placeholder: "New tag name…", text: $newTag) { create() }
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                PrimaryButton(title: "Create", systemImage: "plus") { create() }
            }
            Card {
                if let tags {
                    if tags.isEmpty { EmptyRow(text: "No tags yet.") }
                    ForEach(Array(tags.enumerated()), id: \.element.id) { i, tag in
                        if i > 0 { RowDivider() }
                        HStack(spacing: 10) {
                            Text("#\(tag.name)").font(.system(size: 14, weight: .medium)).foregroundStyle(theme.text200)
                            Text("\(tag.count) item\(tag.count == 1 ? "" : "s")").font(.system(size: 12)).foregroundStyle(theme.textMuted)
                            Spacer()
                            Menu {
                                Button("Rename", systemImage: "pencil") { renameText = tag.name; renaming = tag }
                                Button("Delete", systemImage: "trash", role: .destructive) { deleting = tag }
                            } label: {
                                Image(systemName: "ellipsis").font(.system(size: 14)).foregroundStyle(theme.textMuted)
                                    .frame(width: 32, height: 28).contentShape(Rectangle())
                            }
                        }
                        .padding(.horizontal, 16).padding(.vertical, 11)
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(30)
                }
            }
            Text("Renaming or deleting a tag changes it on every task, note, reminder, routine and bookmark that uses it.")
                .font(.system(size: 12)).foregroundStyle(theme.textMuted).padding(.horizontal, 4)
        }
        .task { if tags == nil { await load() } }
        .alert("Rename #\(renaming?.name ?? "")", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("New name", text: $renameText).textInputAutocapitalization(.never).autocorrectionDisabled()
            Button("Rename") { rename() }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
        .confirmationDialog("Delete #\(deleting?.name ?? "") from all items?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("Delete tag", role: .destructive) { delete() }
        } message: {
            Text("It's removed from \(deleting?.count ?? 0) item\(deleting?.count == 1 ? "" : "s"). The items themselves stay.")
        }
    }

    private func load() async {
        struct R: Decodable { let tags: [Tag] }
        if let r: R = try? await APIClient.shared.get("/settings/tags") { withAnimation { tags = r.tags } }
    }

    private func create() {
        let name = newTag.trimmingCharacters(in: .whitespaces).lowercased()
        guard !name.isEmpty else { return }
        newTag = ""
        toast.run {
            try await APIClient.shared.post("/settings/tags", ["name": name])
            toast.show("#\(name) created")
            await load()
        }
    }

    private func rename() {
        guard let tag = renaming else { return }
        let new = renameText.trimmingCharacters(in: .whitespaces).lowercased()
        renaming = nil
        guard !new.isEmpty, new != tag.name else { return }
        toast.run {
            try await APIClient.shared.post("/settings/tags/rename", ["oldName": tag.name, "newName": new], method: "PUT")
            toast.show("#\(tag.name) renamed to #\(new)")
            await load()
            app.dataChanged()
        }
    }

    private func delete() {
        guard let tag = deleting else { return }
        deleting = nil
        toast.run {
            try await APIClient.shared.post("/settings/tags/delete", ["name": tag.name])
            toast.show("#\(tag.name) deleted from all items")
            await load()
            app.dataChanged()
        }
    }
}

// ── Shortcuts ────────────────────────────────────────────────────────────────
// The web's Shortcuts tab: keys that let the iOS Shortcuts app send captures to your account.

struct ShortcutsTab: View {
    @Environment(Toast.self) private var toast
    @Environment(\.theme) private var theme

    @State private var store = ApiTokensStore()
    @State private var revoking: ApiTokenItem?

    private func when(_ date: Date?) -> String {
        guard let date else { return "never" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    var body: some View {
        Page(refresh: { await store.load() }) {
            if let fresh = store.fresh, let token = fresh.token {
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Save this token now. It will not be shown again.").font(.system(size: 14, weight: .semibold)).foregroundStyle(theme.amber400)
                        Text("Token label: \(fresh.label)").font(.system(size: 12)).foregroundStyle(theme.textMuted)
                        Text(token).font(.system(size: 12, design: .monospaced)).foregroundStyle(theme.text200).textSelection(.enabled)
                        HStack {
                            SecondaryButton(title: "Copy", systemImage: "doc.on.doc") { Clipboard.copy(token); toast.show("Token copied") }
                            SecondaryButton(title: "Done") { store.dismissFresh() }
                        }
                        Text("Treat this like a password. Anyone with this token can add items to your account.").font(.system(size: 12)).foregroundStyle(theme.textMuted)
                    }
                    .padding(16)
                }
            }
            Card {
                CardHeader(title: "API tokens")
                Text("Used by iOS Shortcuts to send captures to your account.").font(.system(size: 12)).foregroundStyle(theme.textMuted)
                    .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 4)
                if store.loaded && store.tokens.isEmpty { EmptyRow(text: "No tokens yet. Create one below to use in your Shortcut.") }
                ForEach(Array(store.tokens.enumerated()), id: \.element.id) { i, t in
                    if i > 0 { RowDivider() }
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(t.label).font(.system(size: 14, weight: .medium)).foregroundStyle(theme.text200)
                            Text("Created \(when(t.createdAt)) · last used \(when(t.lastUsed))").font(.system(size: 12)).foregroundStyle(theme.textMuted)
                        }
                        Spacer()
                        SecondaryButton(title: "Revoke", tint: theme.red400) { revoking = t }
                    }
                    .padding(.horizontal, 20).padding(.vertical, 11)
                }
                RowDivider()
                HStack(spacing: 8) {
                    ThemedField(placeholder: "Token label (e.g. iPhone Shortcut)", text: $store.label) { Task { await store.create() } }
                    PrimaryButton(title: "Create token") { Task { await store.create() } }
                }
                .padding(16)
            }
            Card {
                CardHeader(title: "Capture from iOS Shortcuts")
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(ApiTokensStore.howTo(server: APIClient.shared.serverURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))), id: \.self) { line in
                        Text(line).font(.system(size: 13)).foregroundStyle(theme.text400).textSelection(.enabled)
                    }
                }
                .padding(16)
            }
        }
        .task { await store.load() }
        .onChange(of: store.notice) { _, n in if let n { toast.show(n.text, error: n.isError) } }
        .confirmationDialog(ApiTokensStore.revokeQuestion, isPresented: Binding(get: { revoking != nil }, set: { if !$0 { revoking = nil } }), titleVisibility: .visible) {
            Button("Revoke", role: .destructive) { if let t = revoking { Task { await store.revoke(t) } } }
        }
    }
}
