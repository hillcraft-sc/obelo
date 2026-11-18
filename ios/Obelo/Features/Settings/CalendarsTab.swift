import SwiftUI

// Settings ▸ Calendars: the web's Calendar Sources page. Connected accounts (CalDAV, and Google ones connected
// on the web) with their calendars, your own shareable calendars, and the default calendar for new events.

struct CalendarsTab: View {
    @Environment(Toast.self) private var toast
    @Environment(\.theme) private var theme
    @Environment(AppState.self) private var app
    private var demo: Bool { app.me?.demo == true }

    @State private var store = CalendarSourcesStore()
    @State private var adding = false
    @State private var openAccount: CalendarAccount?
    @State private var openOwn: OwnCalendar?
    @State private var creatingOwn = false

    private func ago(_ date: Date?) -> String {
        guard let date else { return "Never synced" }
        return "Last synced " + date.formatted(date: .abbreviated, time: .shortened)
    }

    var body: some View {
        Page(refresh: { await store.load() }) {
            if let failure = store.failure, store.data == nil { Banner(kind: .error, text: failure) }
            if demo { Banner(kind: .warning, text: "Calendar accounts and notification channels aren't available on the demo. Run your own Obelo server to connect them.") } else { accounts }
            own
            defaultCalendar
        }
        .task { await store.load() }
        .onChange(of: store.notice) { _, text in if let text { toast.show(text); store.dismissMessages() } }
        .onChange(of: store.failure) { _, text in if let text, store.data != nil, !adding, openAccount == nil, openOwn == nil, !creatingOwn { toast.show(text, error: true) } }
        .sheet(isPresented: $adding) { AddAccountSheet(store: store) }
        .sheet(item: $openAccount) { AccountSheet(store: store, account: $0) }
        .sheet(item: $openOwn) { OwnCalendarSheet(store: store, calendarID: $0.id) }
        .sheet(isPresented: $creatingOwn) { OwnCalendarSheet(store: store, calendarID: nil) }
    }

    private func changeDefault(_ value: String) {
        Task { await store.setDefault(value) }
    }

    private var accounts: some View {
        Card {
            CardHeader(title: "Connected")
            if store.data != nil && store.accounts.isEmpty {
                EmptyRow(text: "No calendar accounts yet. Connect one to see its events in Calendar.")
            }
            ForEach(Array(store.accounts.enumerated()), id: \.element.id) { i, account in
                if i > 0 { RowDivider() }
                Button { openAccount = account } label: {
                    HStack(spacing: 12) {
                        Dot(color: Color(hex: account.color), size: 10)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(account.name).font(.system(size: 14, weight: .medium)).foregroundStyle(theme.text200)
                            Text("\(account.kindLabel) · \(account.calendars.count) calendar\(account.calendars.count == 1 ? "" : "s") · \(ago(account.lastSynced))")
                                .font(.system(size: 12)).foregroundStyle(theme.textMuted)
                        }
                        Spacer()
                        if store.syncing.contains(account.id) { ProgressView() }
                        else { Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(theme.textMuted) }
                    }
                    .padding(.horizontal, 20).padding(.vertical, 12).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(account.name), \(account.kindLabel)")
                .accessibilityHint("Opens this account's calendars")
            }
            RowDivider()
            HStack { PrimaryButton(title: "Connect a Calendar", systemImage: "plus") { adding = true }; Spacer() }.padding(16)
        }
    }

    private var own: some View {
        Card {
            CardHeader(title: "Shared Calendars")
            Text("Calendars kept in Obelo, which you can share with other Obelo users.")
                .font(.system(size: 12)).foregroundStyle(theme.textMuted).padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 4)
            if store.data != nil && store.ownCalendars.isEmpty { EmptyRow(text: "No shared calendars yet. Create one to share events with other Obelo users.") }
            ForEach(Array(store.ownCalendars.enumerated()), id: \.element.id) { i, cal in
                if i > 0 { RowDivider() }
                Button { openOwn = cal } label: {
                    HStack(spacing: 12) {
                        Dot(color: Color(hex: cal.color), size: 10)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(cal.name).font(.system(size: 14, weight: .medium)).foregroundStyle(theme.text200)
                            Text(cal.members.isEmpty ? "Only you" : "Shared with " + cal.members.map(\.shownName).joined(separator: ", "))
                                .font(.system(size: 12)).foregroundStyle(theme.textMuted).lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(theme.textMuted)
                    }
                    .padding(.horizontal, 20).padding(.vertical, 12).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(cal.name)
                .accessibilityHint("Opens this calendar's settings and who it is shared with")
            }
            RowDivider()
            HStack { SecondaryButton(title: "+ New calendar") { creatingOwn = true }; Spacer() }.padding(16)
        }
    }

    private var defaultCalendar: some View {
        Card {
            CardHeader(title: "Default Calendar")
            VStack(alignment: .leading, spacing: 8) {
                Text("Pre-selected when creating new events.").font(.system(size: 12)).foregroundStyle(theme.textMuted)
                SelectField(options: store.targets.map { ($0.value, $0.label) },
                            selection: Binding(get: { store.defaultTarget }, set: { changeDefault($0) }))
            }
            .padding(16)
        }
    }
}

// ── Colour ───────────────────────────────────────────────────────────────────

private struct ColourRow: View {
    @Environment(\.theme) private var theme
    @Binding var hex: String
    var body: some View {
        ColorPicker(selection: Binding(get: { Color(hex: hex) }, set: { hex = $0.hexString }), supportsOpacity: false) {
            Text("Color").font(.system(size: 14, weight: .medium)).foregroundStyle(theme.text200)
        }
    }
}

// ── Add a CalDAV account ─────────────────────────────────────────────────────

private struct AddAccountSheet: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    let store: CalendarSourcesStore
    @State private var draft = CaldavDraft()
    @State private var error: String?

    var body: some View {
        FormSheet(title: "Connect a Calendar", saveTitle: "Connect & sync", canSave: draft.canSubmit, error: error, save: {
            error = nil
            if await store.connect(draft) { return true }
            error = store.failure; return false
        }) {
            SectionTabs(tabs: [SectionTab(key: "apple", label: "Apple iCloud"), SectionTab(key: "other", label: "Other CalDAV")],
                        selection: Binding(get: { draft.provider.rawValue }, set: { draft.provider = CaldavDraft.Provider(rawValue: $0) ?? .apple }))
            Text(draft.hint).font(.system(size: 12)).foregroundStyle(theme.textMuted)
            FormSection(label: "Name (optional)") { ThemedField(placeholder: draft.provider == .apple ? "iCloud Calendar" : "My calendar", text: $draft.name) }
            FormSection(label: draft.provider == .apple ? "Apple ID email" : "Username") {
                ThemedField(placeholder: draft.usernamePlaceholder, text: $draft.username)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.emailAddress)
            }
            FormSection(label: draft.provider == .apple ? "App-specific password" : "Password") {
                SecureField("", text: $draft.password, prompt: Text(draft.provider == .apple ? "xxxx-xxxx-xxxx-xxxx" : "Password").foregroundStyle(theme.placeholder))
                    .textContentType(.password).font(.system(size: 15)).foregroundStyle(theme.text100)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(theme.isDark ? theme.elevated : theme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(theme.border2, lineWidth: 1))
            }
            if draft.provider == .other {
                FormSection(label: "Server URL") {
                    ThemedField(placeholder: "https://caldav.example.com", text: $draft.serverUrl)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                }
                FormSection(label: "Calendar home URL (optional)") {
                    ThemedField(placeholder: "https://caldav.example.com/principals/user/", text: $draft.calendarHomeUrl)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                }
            }
            ColourRow(hex: $draft.color)
        }
    }
}

// ── One account: colour, which calendars, the family one, sync, remove ───────

private struct AccountSheet: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    let store: CalendarSourcesStore
    let account: CalendarAccount
    @State private var color: String
    @State private var picked: Set<String>
    @State private var confirmRemove = false

    init(store: CalendarSourcesStore, account: CalendarAccount) {
        self.store = store; self.account = account
        _color = State(initialValue: account.color)
        _picked = State(initialValue: Set(account.calendars.filter(\.selected).map(\.url)))
    }

    var body: some View {
        FormSheet(title: account.name, saveTitle: "Save & sync", canSave: account.calendars.isEmpty || !picked.isEmpty, save: {
            if color != account.color { await store.setColor(account, color) }
            let original = Set(account.calendars.filter(\.selected).map(\.url))
            if !account.calendars.isEmpty, picked != original { await store.setCalendars(account, urls: account.calendars.map(\.url).filter(picked.contains)) }
            return true
        }) {
            Text("\(account.kindLabel) · " + (account.lastSynced.map { "Last synced " + $0.formatted(date: .abbreviated, time: .shortened) } ?? "Never synced") + (account.isFamily ? " · Family calendar" : ""))
                .font(.system(size: 12)).foregroundStyle(theme.textMuted)
            ColourRow(hex: $color)
            if !account.calendars.isEmpty {
                FormSection(label: "Calendars to sync (\(picked.count == account.calendars.count ? "all" : String(picked.count))/\(account.calendars.count))") {
                    VStack(spacing: 0) {
                        ForEach(Array(account.calendars.enumerated()), id: \.element.id) { i, cal in
                            if i > 0 { RowDivider() }
                            Toggle(isOn: Binding(get: { picked.contains(cal.url) }, set: { on in
                                if on { picked.insert(cal.url) } else { picked.remove(cal.url) }
                            })) {
                                HStack(spacing: 8) {
                                    Dot(color: Color(hex: cal.color ?? account.color))
                                    Text(cal.name).font(.system(size: 14)).foregroundStyle(theme.text200)
                                }
                            }
                            .padding(.vertical, 8)
                        }
                    }
                }
                if picked.isEmpty { Text("Keep at least one calendar ticked.").font(.system(size: 12)).foregroundStyle(theme.amber400) }
            }
            SecondaryButton(title: store.syncing.contains(account.id) ? "Syncing…" : "Sync now", systemImage: "arrow.triangle.2.circlepath") {
                Task { await store.sync(account) }
            }
            .disabled(store.syncing.contains(account.id))
            SecondaryButton(title: "Remove account", systemImage: "trash", tint: theme.red400) { confirmRemove = true }
        }
        .confirmationDialog("Remove this calendar?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove", role: .destructive) { Task { await store.remove(account); dismiss() } }
        } message: {
            Text("All synced events will be deleted.")
        }
    }
}

// ── Your own calendar: name, colour, who it is shared with ───────────────────

private struct OwnCalendarSheet: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    let store: CalendarSourcesStore
    let calendarID: Int?
    @State private var name = ""
    @State private var color = "#6366f1"
    @State private var person = ""
    @State private var error: String?
    @State private var confirmDelete = false
    @State private var loaded = false

    private var calendar: OwnCalendar? { store.ownCalendars.first { $0.id == calendarID } }

    var body: some View {
        FormSheet(title: calendarID == nil ? "New Shared Calendar" : "Shared Calendar", saveTitle: calendarID == nil ? "Create" : "Save",
                  canSave: !name.trimmingCharacters(in: .whitespaces).isEmpty, error: error, save: {
            error = nil
            if let calendar { await store.updateOwn(calendar, name: name, color: color); return true }
            if await store.createOwn(name: name, color: color) { return true }
            error = store.failure; return false
        }) {
            FormSection(label: "Calendar name") { ThemedField(placeholder: "e.g. Family, Work Team", text: $name) }
            ColourRow(hex: $color)
            if let calendar {
                FormSection(label: "Shared with:") {
                    VStack(alignment: .leading, spacing: 0) {
                        if calendar.members.isEmpty { Text("Not shared with anyone yet.").font(.system(size: 13)).foregroundStyle(theme.textMuted).padding(.vertical, 6) }
                        ForEach(calendar.members) { m in
                            HStack {
                                Text(m.shownName).font(.system(size: 14)).foregroundStyle(theme.text200)
                                                                Spacer()
                                SecondaryButton(title: "Remove", tint: theme.red400) { Task { await store.removeMember(calendar, m) } }
                                    .accessibilityLabel("Remove \(m.shownName)")
                            }
                            .padding(.vertical, 6)
                        }
                    }
                }
                HStack(spacing: 8) {
                    ThemedField(placeholder: "Add by username", text: $person).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecondaryButton(title: "Add") {
                        Task { if await store.addMember(calendar, username: person) { person = "" } else { error = store.failure } }
                    }
                    .disabled(person.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Menu {
                    ForEach(store.peopleToAdd(to: calendar)) { u in Button(u.displayName ?? u.username) { person = u.username } }
                } label: {
                    Text("Choose from people on this server").font(.system(size: 13)).foregroundStyle(theme.accentText)
                }
                .disabled(store.peopleToAdd(to: calendar).isEmpty)
                SecondaryButton(title: "Delete calendar", systemImage: "trash", tint: theme.red400) { confirmDelete = true }
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if let calendar { name = calendar.name; color = calendar.color }
        }
        .confirmationDialog("Delete \(name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { if let calendar { Task { await store.deleteOwn(calendar); dismiss() } } }
        } message: {
            Text("Events in this calendar will be kept but unlinked from the calendar.")
        }
    }
}
