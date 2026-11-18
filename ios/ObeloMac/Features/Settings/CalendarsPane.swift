import SwiftUI

/// Settings ▸ Calendars: the web's Calendar Sources page (`/calendar/sources`), matched to it
/// Connected accounts with the calendars each one syncs, the default calendar for new
/// events, your own shared calendars, and the form that connects a CalDAV account.
struct CalendarsPane: View {
    @Environment(AppState.self) private var app
    @Environment(\.theme) private var theme
    @Bindable var hub: SettingsHub
    private var demo: Bool { app.me?.demo == true }
    @State private var notice: SettingsNotice?
    @State private var removing: CalendarAccount?
    @State private var deleting: OwnCalendar?
    @State private var editing: OwnCalendarEdit?
    @State private var draft = CaldavDraft()
    @State private var connecting = false
    @State private var connectError: String?
    @State private var defaultChoice = "local"

    private var store: CalendarSourcesStore { hub.calendars }

    var body: some View {
        SettingsPage(notice: $notice) {
            if demo { KitBanner(kind: .warn, text: "Calendar accounts and notification channels aren't available on the demo. Run your own Obelo server to connect them.") } else { connected }
            if store.targets.count > 1 { defaultCalendar }
            shared
            if !demo { connect }
        }
        .task { await store.load(); defaultChoice = store.defaultTarget }
        .onChange(of: store.defaultTarget) { _, value in defaultChoice = value }
        .onChange(of: store.notice) { _, text in if let text { notice = SettingsNotice(text: text, isError: false); store.dismissMessages() } }
        .onChange(of: store.failure) { _, text in if let text { notice = SettingsNotice(text: text, isError: true); store.dismissMessages() } }
        .kitConfirm("Remove this calendar?", item: $removing, confirmLabel: "Remove", destructive: true,
                    message: "All synced events will be deleted.") { account in Task { await store.remove(account) } }
        .kitConfirm("Delete this calendar?", item: $deleting, confirmLabel: "Delete", destructive: true,
                    message: "Events in this calendar will be kept but unlinked from the calendar.") { cal in Task { await store.deleteOwn(cal) } }
        .sheet(item: $editing) { OwnCalendarSheet(store: store, edit: $0) }
    }

    // ── Connected ───────────────────────────────────────────────────────────

    @ViewBuilder private var connected: some View {
        SettingsCard(title: "Connected") {
            if store.data != nil && store.accounts.isEmpty {
                Text("No calendar accounts yet. Connect one below to see its events in Calendar.")
                    .font(.system(size: 14)).italic().foregroundStyle(theme.textMuted)
            }
            ForEach(store.accounts) { account in
                AccountBlock(store: store, account: account, hour12: app.hour12, remove: { removing = account })
                    .id(account.id)
                    .overlay(alignment: .bottom) { if account.id != store.accounts.last?.id { KitDivider() } }
            }
        }
    }

    // ── Default Calendar ────────────────────────────────────────────────────

    private var defaultCalendar: some View {
        SettingsCard(title: "Default Calendar", detail: "Pre-selected when creating new events.") {
            HStack(spacing: 10) {
                KitSelect(options: store.targets.map { (value: $0.value, label: $0.label) }, selection: $defaultChoice, label: "Default calendar")
                Button("Save") { Task { await store.setDefault(defaultChoice) } }
                    .buttonStyle(KitButtonStyle(.primary)).disabled(defaultChoice == store.defaultTarget)
            }
        }
    }

    // ── Shared Calendars ────────────────────────────────────────────────────

    private var shared: some View {
        KitCard {
            KitCardHeader(title: "Shared Calendars") {
                Button("+ New calendar") { editing = OwnCalendarEdit(calendar: nil) }.buttonStyle(KitButtonStyle(.secondary, small: true))
            }
            VStack(alignment: .leading, spacing: 0) {
                if store.data != nil && store.ownCalendars.isEmpty {
                    Text("No shared calendars yet. Create one to share events with other Obelo users.")
                        .font(.system(size: 14)).foregroundStyle(theme.textMuted).padding(20)
                }
                ForEach(store.ownCalendars) { cal in
                    SharedBlock(store: store, calendar: cal, rename: { editing = OwnCalendarEdit(calendar: cal) }, delete: { deleting = cal })
                        .id(cal.id)
                        .overlay(alignment: .bottom) { if cal.id != store.ownCalendars.last?.id { KitDivider() } }
                }
            }
        }
    }

    // ── Connect a Calendar ──────────────────────────────────────────────────

    private var connect: some View {
        SettingsCard(title: "Connect a Calendar") {
            KitPillSelector(options: [(value: CaldavDraft.Provider.apple, label: "Apple iCloud"), (value: .other, label: "Other CalDAV")],
                            selection: $draft.provider, label: "Calendar provider")
            Text(draft.hint).font(.system(size: 12)).foregroundStyle(theme.textMuted).fixedSize(horizontal: false, vertical: true)
            KitFieldLabel(text: "Name (optional)") { KitTextField(placeholder: draft.provider == .apple ? "iCloud Calendar" : "My calendar", text: $draft.name) }
            KitFieldLabel(text: draft.provider == .apple ? "Apple ID email" : "Username") {
                KitTextField(placeholder: draft.usernamePlaceholder, text: $draft.username, contentType: .username)
            }
            KitFieldLabel(text: draft.provider == .apple ? "App-specific password" : "Password") {
                KitSecureField(placeholder: draft.provider == .apple ? "xxxx-xxxx-xxxx-xxxx" : "Password", text: $draft.password, onSubmit: submit)
            }
            if draft.provider == .other {
                KitFieldLabel(text: "Server URL") { KitTextField(placeholder: "https://caldav.example.com", text: $draft.serverUrl) }
                KitFieldLabel(text: "Calendar home URL (optional)") { KitTextField(placeholder: "https://caldav.example.com/principals/user/", text: $draft.calendarHomeUrl) }
            }
            KitFieldLabel(text: "Color") { KitColorField(hex: $draft.color, label: "Calendar colour") }
            if let connectError { KitBanner(kind: .error, text: connectError) }
            HStack {
                Button("Connect & sync", action: submit)
                    .buttonStyle(KitButtonStyle(.primary, busy: connecting)).disabled(!draft.canSubmit || connecting)
                    .keyboardShortcut(.defaultAction)
                Spacer()
            }
        }
    }

    private func submit() {
        guard draft.canSubmit, !connecting else { return }
        connecting = true; connectError = nil
        Task {
            defer { connecting = false }
            if await store.connect(draft) { draft = CaldavDraft() }
            else { connectError = notice?.text ?? "Could not connect." }
        }
    }
}

// ── One connected account ────────────────────────────────────────────────────

private struct AccountBlock: View {
    @Environment(\.theme) private var theme
    let store: CalendarSourcesStore
    let account: CalendarAccount
    let hour12: Bool
    let remove: () -> Void
    @State private var color: String
    @State private var picked: Set<String>
    @State private var open: Bool

    init(store: CalendarSourcesStore, account: CalendarAccount, hour12: Bool, remove: @escaping () -> Void) {
        self.store = store; self.account = account; self.hour12 = hour12; self.remove = remove
        _color = State(initialValue: account.color)
        _picked = State(initialValue: Set(account.calendars.filter(\.selected).map(\.url)))
        _open = State(initialValue: account.calendars.count <= 1)
    }

    private var syncing: Bool { store.syncing.contains(account.id) }
    private var allShown: String { picked.count == account.calendars.count ? "all" : String(picked.count) }

    private var caption: String {
        var text = account.kindLabel.uppercased() == "CALDAV" ? "CALDAV" : account.kindLabel
        if let d = account.lastSynced {
            let f = DateFormatter(); f.dateFormat = hour12 ? "MMM d, h:mm a" : "MMM d, HH:mm"   // the web: "Nov 15, 3:05 PM"
            text += " · Last synced " + f.string(from: d)
        } else { text += " · Never synced" }
        if account.isFamily { text += " · Family calendar" }
        return text
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                KitColorSwatch(hex: $color, label: "Colour of \(account.name)")
                VStack(alignment: .leading, spacing: 1) {
                    Text(account.name).font(.system(size: 14, weight: .medium)).foregroundStyle(theme.text100)
                    Text(caption).font(.system(size: 12)).foregroundStyle(theme.textMuted)
                }
                Spacer()
                Button("Sync now") { Task { await store.sync(account) } }
                    .buttonStyle(KitButtonStyle(.secondary, small: true, busy: syncing)).disabled(syncing)
                Button("Remove", action: remove).buttonStyle(KitButtonStyle(.danger, small: true)).disabled(syncing)
            }
            if !account.calendars.isEmpty {
                KitDisclosure(title: "Calendars to sync (\(allShown)/\(account.calendars.count))", isOpen: $open) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(account.calendars) { cal in
                            KitCheckbox(title: cal.name, isOn: Binding(get: { picked.contains(cal.url) }, set: { on in
                                if on { picked.insert(cal.url) } else { picked.remove(cal.url) }
                            }))
                        }
                    }
                    HStack(spacing: 10) {
                        Button("Save & sync") {
                            Task { await store.setCalendars(account, urls: account.calendars.map(\.url).filter(picked.contains)) }
                        }
                        .buttonStyle(KitButtonStyle(.primary, small: true, busy: syncing))
                        .disabled(picked.isEmpty || syncing || picked == Set(account.calendars.filter(\.selected).map(\.url)))
                        Text(picked.isEmpty ? "Tick at least one calendar." : "saves selection and re-syncs").font(.system(size: 12)).foregroundStyle(theme.textMuted)
                    }
                }
            }
        }
        // A colour chosen in the panel is saved once you stop moving it
        .task(id: color) {
            guard color != account.color else { return }
            try? await Task.sleep(for: .milliseconds(700))
            if !Task.isCancelled { await store.setColor(account, color) }
        }
        .contextMenu {
            Button("Sync now") { Task { await store.sync(account) } }
            Button("Remove…", role: .destructive, action: remove)
        }
        .padding(.vertical, 10)
    }
}

// ── One shared calendar ──────────────────────────────────────────────────────

private struct SharedBlock: View {
    @Environment(\.theme) private var theme
    let store: CalendarSourcesStore
    let calendar: OwnCalendar
    let rename: () -> Void
    let delete: () -> Void
    @State private var color: String
    @State private var person = ""

    init(store: CalendarSourcesStore, calendar: OwnCalendar, rename: @escaping () -> Void, delete: @escaping () -> Void) {
        self.store = store; self.calendar = calendar; self.rename = rename; self.delete = delete
        _color = State(initialValue: calendar.color)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                KitColorSwatch(hex: $color, label: "Colour of \(calendar.name)")
                Text(calendar.name).font(.system(size: 14, weight: .medium)).foregroundStyle(theme.text100)
                Spacer()
                Button("Delete", action: delete).buttonStyle(KitButtonStyle(.danger, small: true))
            }
            if calendar.members.isEmpty {
                Text("Not shared with anyone yet.").font(.system(size: 12)).foregroundStyle(theme.textMuted)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Shared with:").font(.system(size: 12)).foregroundStyle(theme.textMuted)
                    ForEach(calendar.members) { m in
                        HStack {
                            Text(m.shownName).font(.system(size: 13)).foregroundStyle(theme.text300)
                            Spacer()
                            Button("remove") { Task { await store.removeMember(calendar, m) } }
                                .buttonStyle(KitButtonStyle(.ghost, small: true))
                                .accessibilityLabel("Remove \(m.shownName) from \(calendar.name)")
                        }
                    }
                }
            }
            HStack(spacing: 8) {
                KitTextField(placeholder: "Add by username", text: $person, onSubmit: add)
                KitActionMenu(title: "People") {
                    ForEach(store.peopleToAdd(to: calendar)) { u in Button(u.displayName.map { "\($0) (@\(u.username))" } ?? "@\(u.username)") { person = u.username } }
                }
                .disabled(store.peopleToAdd(to: calendar).isEmpty)
                Button("Add", action: add).buttonStyle(KitButtonStyle(.primary, small: true)).disabled(person.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .task(id: color) {
            guard color != calendar.color else { return }
            try? await Task.sleep(for: .milliseconds(700))
            if !Task.isCancelled { await store.updateOwn(calendar, name: calendar.name, color: color) }
        }
        .contextMenu {
            Button("Rename…", action: rename)
            Button("Delete…", role: .destructive, action: delete)
        }
        .padding(16)
    }

    private func add() {
        Task { if await store.addMember(calendar, username: person) { person = "" } }
    }
}

// ── New or rename a shared calendar ──────────────────────────────────────────

struct OwnCalendarEdit: Identifiable {
    let calendar: OwnCalendar?
    var id: Int { calendar?.id ?? -1 }
}

private struct OwnCalendarSheet: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    let store: CalendarSourcesStore
    let edit: OwnCalendarEdit
    @State private var name: String
    @State private var color: String
    @State private var error: String?

    init(store: CalendarSourcesStore, edit: OwnCalendarEdit) {
        self.store = store; self.edit = edit
        _name = State(initialValue: edit.calendar?.name ?? "")
        _color = State(initialValue: edit.calendar?.color ?? "#6366f1")
    }

    private var valid: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(edit.calendar == nil ? "New Shared Calendar" : "Rename Calendar").font(.system(size: 16, weight: .semibold)).foregroundStyle(theme.text100)
            KitFieldLabel(text: "Calendar name") { KitTextField(placeholder: "e.g. Family, Work Team", text: $name, onSubmit: save) }
            KitFieldLabel(text: "Color") { KitColorField(hex: $color, label: "Calendar colour") }
            if let error { KitBanner(kind: .error, text: error) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(KitButtonStyle(.secondary)).keyboardShortcut(.cancelAction)
                Button(edit.calendar == nil ? "Create" : "Save", action: save).buttonStyle(KitButtonStyle(.primary)).disabled(!valid)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24).frame(width: 420).background(theme.page)
    }

    private func save() {
        guard valid else { return }
        Task {
            if let cal = edit.calendar { await store.updateOwn(cal, name: name, color: color); dismiss(); return }
            if await store.createOwn(name: name, color: color) { dismiss() } else { error = store.failure }
        }
    }
}
