import UniformTypeIdentifiers
import PhotosUI
import SwiftUI

// Settings — views/settings/index.ejs with the same tabs. Account, Modules, Appearance and
// Dashboard are native; the rest (notifications, notes, tags, data) still open on the web.
// Toggles and reordering save immediately; text fields save with the Save button.

struct SettingsView: View {
    @Environment(AppState.self) private var app
    @Environment(Toast.self) private var toast
    @Environment(\.theme) private var theme

    @State private var tab = "account"
    @State private var data: SettingsData?
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                PageHeader(title: "Settings", subtitle: "Your account and app preferences.", pageName: true)
                // Same tabs, same order as the web
                SectionTabs(tabs: [
                    SectionTab(key: "account", label: "Account"), SectionTab(key: "modules", label: "Modules"),
                    SectionTab(key: "notifications", label: "Notifications"), SectionTab(key: "appearance", label: "Appearance"),
                    SectionTab(key: "notes", label: "Notes"), SectionTab(key: "calendars", label: "Calendars"), SectionTab(key: "dashboard", label: "Dashboard"),
                    SectionTab(key: "tags", label: "Tags"), SectionTab(key: "shortcuts", label: "Shortcuts"), SectionTab(key: "data", label: "Data"),
                ], selection: $tab)
            }
            .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 4)

            // These tabs load their own data
            if tab == "notifications" { NotificationsTab() }
            else if tab == "notes" { NotesSettingsTab() }
            else if tab == "calendars" { CalendarsTab() }
            else if tab == "tags" { TagsTab() }
            else if tab == "shortcuts" { ShortcutsTab() }
            else if tab == "data" { DataTab() }
            else if let error, data == nil {
                Banner(kind: .error, text: error).padding(16)
                Spacer()
            } else if let binding = Binding($data) {
                switch tab {
                case "modules": ModulesTab(modules: binding.modules)
                case "appearance": AppearanceTab(look: binding.appearance)
                case "dashboard": DashboardTab(widgets: binding.dashboard)
                default: AccountTab(account: binding.account, reload: load)
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(theme.page)
        .task { await load() }
        #if DEBUG
        .onAppear { if let t = UserDefaults.standard.string(forKey: "settingsTab") { tab = t } } // simulator testing
        #endif
    }

    private func load() async {
        do { data = try await APIClient.shared.get("/settings"); error = nil }
        catch { self.error = error.localizedDescription }
    }
}

// ── Account ──────────────────────────────────────────────────────────────────

private struct AccountTab: View {
    @Environment(AppState.self) private var app
    @Environment(Toast.self) private var toast
    @Environment(\.theme) private var theme
    @Binding var account: SettingsData.Account
    let reload: () async -> Void

    @State private var displayName = ""
    @State private var email = ""
    @State private var timezone = ""
    @State private var timeFormat = "12h"
    @State private var saving = false
    @State private var formError: String?
    @State private var loaded = false
    @State private var pickingZone = false
    @State private var photoItem: PhotosPickerItem?
    @State private var showLibrary = false
    @State private var showCamera = false
    @State private var sessions: [DeviceSession] = []
    @State private var confirmSignOut = false
    @State private var confirmEndOthers = false
    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var newPasswordAgain = ""
    @State private var passwordError: String?
    @State private var savingPassword = false

    private var dirty: Bool {
        displayName != account.displayName || email != account.email || timezone != account.timezone || timeFormat != account.timeFormat
    }

    var body: some View {
        Page(refresh: { await reload(); await loadSessions() }) {
            Card(padding: 20) {
                HStack(spacing: 14) {
                    Menu {
                        Button("Choose Photo", systemImage: "photo.on.rectangle") { showLibrary = true }
                        #if os(iOS)
                        if UIImagePickerController.isSourceTypeAvailable(.camera) {
                            Button("Take Photo", systemImage: "camera") { showCamera = true }
                        }
                        #endif
                        if account.hasCustomAvatar {
                            Button("Remove Photo", systemImage: "trash", role: .destructive) { removeAvatar() }
                        }
                    } label: {
                        AvatarView(url: account.avatarUrl, name: account.displayName, size: 56)
                            .overlay(alignment: .bottomTrailing) {
                                Image(systemName: "camera.fill").font(.system(size: 10)).foregroundStyle(theme.onAccent)
                                    .frame(width: 20, height: 20).background(theme.accent, in: Circle())
                                    .overlay(Circle().stroke(theme.surface, lineWidth: 2))
                            }
                    }
                    .accessibilityLabel("Change profile photo")
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Profile").font(.system(size: 14, weight: .semibold)).foregroundStyle(theme.textPrimary)
                        Text("@\(account.username)").font(.system(size: 13)).foregroundStyle(theme.textMuted)
                    }
                    Spacer()
                    if app.me?.user.role == "admin" { Badge(text: "admin", fg: theme.accentTextLight, bg: theme.accentSurface) }
                }
                VStack(alignment: .leading, spacing: 16) {
                    if let formError { Banner(kind: .error, text: formError) }
                    FormSection(label: "Display name") { ThemedField(placeholder: "Your name", text: $displayName) }
                    FormSection(label: "Email address") {
                        ThemedField(placeholder: "you@example.com", text: $email)
                            .keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                    }
                    FormSection(label: "Time format") {
                        Picker("Time format", selection: $timeFormat) {
                            Text("12-hour (2:30 PM)").tag("12h")
                            Text("24-hour (14:30)").tag("24h")
                        }
                        .pickerStyle(.segmented).labelsHidden()
                    }
                    FormSection(label: "Timezone") {
                        Button { pickingZone = true } label: {
                            HStack {
                                Text(timezone.replacingOccurrences(of: "_", with: " ")).font(.system(size: 15)).foregroundStyle(theme.text100)
                                Spacer()
                                Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(theme.textMuted)
                            }
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .background(theme.isDark ? theme.elevated : theme.surface, in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.border2, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                    PrimaryButton(title: "Save", fullWidth: true, busy: saving) { save() }
                        .disabled(!dirty)
                        .opacity(dirty ? 1 : 0.5)
                }
                .padding(.top, 20)
            }

            // Not on the public demo: everyone signs in with the shared demo account
            if account.passwordLogin == true && app.me?.demo != true { passwordCard }

            devices

            SecondaryButton(title: "Sign out", systemImage: "rectangle.portrait.and.arrow.right", tint: theme.red400) { confirmSignOut = true }
            Text("Obelo \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") · server v\(app.me?.version ?? "?") · \(APIClient.shared.serverURL.host() ?? "")")
                .font(.system(size: 11, design: .monospaced)).foregroundStyle(theme.textMuted)
                .frame(maxWidth: .infinity)
        }
        .task {
            if !loaded { loaded = true; reset() }
            await loadSessions()
        }
        .onChange(of: account.displayName) { reset() }
        .sheet(isPresented: $pickingZone) { TimezonePicker(selection: $timezone) }
        .photosPicker(isPresented: $showLibrary, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            photoItem = nil
            Task {
                if let d = try? await item.loadTransferable(type: Data.self), let image = PlatformImage(data: d) { await uploadAvatar(image) }
            }
        }
        #if os(iOS)
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { image in Task { await uploadAvatar(image) } }.ignoresSafeArea()
        }
        #endif
        .confirmationDialog("Sign out of Obelo on this device?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) { Task { await app.signOut() } }
        }
        .confirmationDialog("Sign out every other device?", isPresented: $confirmEndOthers, titleVisibility: .visible) {
            Button("Sign out others", role: .destructive) { endOthers() }
        } message: {
            Text("This device stays signed in.")
        }
    }

    private var passwordCard: some View {
        let has = account.hasPassword == true
        return Card(padding: 20) {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(has ? "Password" : "Add a password").font(.system(size: 14, weight: .semibold)).foregroundStyle(theme.textPrimary)
                    Text(has ? "Changing it signs you out of your other devices."
                             : "You sign in with SSO now. A password lets you sign in without it too.")
                        .font(.system(size: 12)).foregroundStyle(theme.textMuted)
                }
                if let passwordError { Banner(kind: .error, text: passwordError) }
                if has { passwordField("Current password", $currentPassword, isNew: false) }
                passwordField("New password (at least 10 characters)", $newPassword, isNew: true)
                passwordField("New password again", $newPasswordAgain, isNew: true)
                PrimaryButton(title: has ? "Change password" : "Save password", fullWidth: true, busy: savingPassword) { savePassword() }
                    .disabled(newPassword.isEmpty || (has && currentPassword.isEmpty))
                    .opacity(newPassword.isEmpty || (has && currentPassword.isEmpty) ? 0.5 : 1)
            }
        }
    }

    private func passwordField(_ placeholder: String, _ text: Binding<String>, isNew: Bool) -> some View {
        SecureField("", text: text, prompt: Text(placeholder).foregroundStyle(theme.placeholder))
            .textContentType(isNew ? .newPassword : .password)
            .font(.system(size: 15)).foregroundStyle(theme.text100)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(theme.isDark ? theme.elevated : theme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(theme.border2, lineWidth: 1))
    }

    private func savePassword() {
        passwordError = nil
        guard newPassword == newPasswordAgain else { passwordError = "The two new passwords don't match"; return }
        savingPassword = true
        Task {
            defer { savingPassword = false }
            do {
                try await APIClient.shared.post("/settings/password", [
                    "currentPassword": currentPassword, "newPassword": newPassword,
                ])
                currentPassword = ""; newPassword = ""; newPasswordAgain = ""
                account.hasPassword = true
                toast.show("Password saved")
                await loadSessions()
            } catch {
                passwordError = error.localizedDescription
            }
        }
    }

    private var devices: some View {
        Card {
            CardHeader(title: "Signed-in devices") {
                if sessions.contains(where: { !$0.current }) {
                    Button("Sign out others") { confirmEndOthers = true }
                        .font(.system(size: 12)).foregroundStyle(theme.red400)
                }
            }
            ForEach(Array(sessions.enumerated()), id: \.element.id) { i, s in
                if i > 0 { RowDivider() }
                HStack(spacing: 12) {
                    Image(systemName: s.device.contains("iPhone") || s.device.contains("app") ? "iphone" : s.device.contains("iPad") ? "ipad" : "desktopcomputer")
                        .font(.system(size: 16)).foregroundStyle(theme.text400).frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(s.device).font(.system(size: 14, weight: .medium)).foregroundStyle(theme.text200)
                            if s.current { Badge(text: "This device", fg: theme.green400, bg: theme.green500.opacity(0.15)) }
                        }
                        Text([s.ip, s.lastSeenAt.map { "active \($0.formatted(.relative(presentation: .named)))" }].compactMap { $0 }.joined(separator: " · "))
                            .font(.system(size: 12)).foregroundStyle(theme.textMuted)
                    }
                    Spacer()
                    if !s.current {
                        Button("Sign out") {
                            toast.run {
                                try await APIClient.shared.post("/sessions/\(s.key)/end")
                                toast.show("Device signed out")
                                await loadSessions()
                            }
                        }
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(theme.red400)
                    }
                }
                .padding(.horizontal, 20).padding(.vertical, 12)
            }
        }
    }

    private func reset() {
        displayName = account.displayName; email = account.email
        timezone = account.timezone; timeFormat = account.timeFormat
    }

    private func save() {
        formError = nil
        saving = true
        Task {
            defer { saving = false }
            do {
                try await APIClient.shared.post("/settings/account", [
                    "displayName": displayName, "email": email, "timezone": timezone, "timeFormat": timeFormat,
                ], method: "PUT")
                account.displayName = displayName.trimmingCharacters(in: .whitespaces).isEmpty ? account.displayName : displayName
                account.email = email; account.timezone = timezone; account.timeFormat = timeFormat
                toast.show("Account updated")
                try? await app.loadMe()   // name, time format and timezone show everywhere
                app.dataChanged()
            } catch {
                formError = error.localizedDescription
            }
        }
    }

    private func uploadAvatar(_ image: PlatformImage) async {
        guard let jpeg = NoteAttachmentsCard.jpeg(image, maxSide: 1024) else { return }
        do {
            let _: EmptyResponse = try await APIClient.shared.upload("/settings/avatar", field: "avatar", data: jpeg, filename: "avatar.jpg", mimeType: "image/jpeg")
            AvatarView.bustCache()
            await reload()
            try? await app.loadMe()
            toast.show("Photo updated")
        } catch {
            toast.show(error.localizedDescription, error: true)
        }
    }

    private func removeAvatar() {
        toast.run {
            try await APIClient.shared.delete("/settings/avatar")
            AvatarView.bustCache()
            await reload()
            try? await app.loadMe()
            toast.show("Photo removed")
        }
    }

    private func loadSessions() async {
        struct R: Decodable { let sessions: [DeviceSession] }
        if let r: R = try? await APIClient.shared.get("/sessions") { sessions = r.sessions }
    }

    private func endOthers() {
        toast.run {
            struct R: Decodable { let ended: Int }
            let r: R = try await APIClient.shared.post("/sessions/end-others")
            toast.show(r.ended == 0 ? "No other devices were signed in" : "Signed out \(r.ended) other device\(r.ended == 1 ? "" : "s")")
            await loadSessions()
        }
    }
}

/// Searchable list of every timezone, with the web's common ones first
private struct TimezonePicker: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: String
    @State private var query = ""

    private static let common = [
        "America/New_York", "America/Chicago", "America/Denver", "America/Los_Angeles", "America/Phoenix",
        "America/Anchorage", "Pacific/Honolulu", "Europe/London", "Europe/Paris", "Europe/Berlin",
        "Asia/Tokyo", "Asia/Shanghai", "Asia/Kolkata", "Australia/Sydney",
    ]

    private var results: [String] {
        let all = TimeZone.knownTimeZoneIdentifiers
        guard !query.isEmpty else { return Self.common + all.filter { !Self.common.contains($0) } }
        let q = query.lowercased().replacingOccurrences(of: " ", with: "_")
        return all.filter { $0.lowercased().contains(q) }
    }

    var body: some View {
        NavigationStack {
            List(results, id: \.self) { tz in
                Button {
                    selection = tz
                    dismiss()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tz.replacingOccurrences(of: "_", with: " ")).foregroundStyle(theme.text100)
                            if let zone = TimeZone(identifier: tz) {
                                Text(zone.localizedName(for: .standard, locale: .current) ?? "").font(.caption).foregroundStyle(theme.textMuted)
                            }
                        }
                        Spacer()
                        if tz == selection { Image(systemName: "checkmark").foregroundStyle(theme.accentText) }
                    }
                }
                .listRowBackground(theme.surface)
            }
            .scrollContentBackground(.hidden)
            .background(theme.page)
            .searchable(text: $query, prompt: "Search timezones")
            .themedNavBar(theme, title: "Timezone")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .presentationBackground(theme.page)
    }
}

// ── Modules ──────────────────────────────────────────────────────────────────

private struct ModulesTab: View {
    @Environment(AppState.self) private var app
    @Environment(Toast.self) private var toast
    @Environment(\.theme) private var theme
    @Binding var modules: [SettingsData.Module]
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    /// The bottom bar (iPhone, and a narrow iPad) is where the order matters; the sidebar groups modules in a fixed order
    private var hasBottomBar: Bool {
        #if os(iOS)
        sizeClass == .compact
        #else
        false
        #endif
    }

    /// The modules that sit in the bottom bar (BottomBar in Shell.swift)
    private var barKeys: Set<String> {
        Set(BottomBar.keys(enabled: modules.filter(\.enabled).map(\.key)))
    }

    /// The bottom bar's order is the saved order; where there is a sidebar the rows are listed in the sidebar's order
    private var displayOrder: [Int] {
        hasBottomBar ? Array(modules.indices) : modules.indices.sorted { SidebarGroups.sortRank(modules[$0].key) < SidebarGroups.sortRank(modules[$1].key) }
    }

    var body: some View {
        List {
            Section {
                ForEach(displayOrder, id: \.self) { i in
                    HStack(spacing: 12) {
                        Image(systemName: ModuleMeta.of(modules[i].key).icon).foregroundStyle(modules[i].enabled ? theme.accentText : theme.textMuted).frame(width: 22)
                        Text(modules[i].label).foregroundStyle(modules[i].enabled ? theme.text100 : theme.textMuted)
                        if hasBottomBar && barKeys.contains(modules[i].key) {
                            Text("Bottom bar").font(.system(size: 10, weight: .medium)).foregroundStyle(theme.accentText)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(theme.accent.opacity(0.2), in: RoundedRectangle(cornerRadius: 4))
                        }
                        Spacer()
                        if modules[i].alwaysEnabled {
                            Text("Always on").font(.caption).foregroundStyle(theme.textMuted)
                        } else {
                            Toggle("", isOn: $modules[i].enabled).labelsHidden().tint(theme.accent)
                                .onChange(of: modules[i].enabled) { save() }
                        }
                    }
                    .listRowBackground(theme.surface)
                    .moveDisabled(modules[i].alwaysEnabled || !hasBottomBar)
                }
                .onMove { from, to in
                    modules.move(fromOffsets: from, toOffset: to)
                    // Today stays first and Settings last, as on the web
                    if let i = modules.firstIndex(where: { $0.key == "dashboard" }), i != 0 { modules.insert(modules.remove(at: i), at: 0) }
                    if let i = modules.firstIndex(where: { $0.key == "settings" }), i != modules.count - 1 { modules.append(modules.remove(at: i)) }
                    save()
                }
            } footer: {
                Text(hasBottomBar
                     ? "Drag to reorder. Today and the first four modules that are on make up the bottom bar; the rest are under More."
                     : "Switch modules on or off. The sidebar groups them in a fixed order; the bottom bar's order is set on iPhone.")
                    .foregroundStyle(theme.textMuted)
            }
        }
        .alwaysEditing()
        .scrollContentBackground(.hidden)
        .contentMargins(.bottom, 80)
    }

    private func save() {
        let body = modules.map { ["key": $0.key, "enabled": $0.enabled] as [String: Any] }
        toast.run {
            try await APIClient.shared.post("/settings/modules", ["modules": body], method: "PUT")
            try? await app.loadMe() // bottom bar and More sheet follow
        }
    }
}

// ── Appearance ───────────────────────────────────────────────────────────────

private struct AppearanceTab: View {
    @Environment(AppState.self) private var app
    @Environment(Toast.self) private var toast
    @Environment(\.theme) private var theme
    @Binding var look: SettingsData.Look

    var body: some View {
        Page {
            Card {
                CardHeader(title: "Theme")
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(Theme.builtIn, id: \.id) { t in tile(t, id: t.id) }
                    tile(Theme.resolve(Appearance(theme: "custom", isDark: look.customBase != "light", customAccent: look.customAccent, customBase: look.customBase)), id: "custom")
                }
                .padding(16)
            }
            if look.theme.hasPrefix("ctp-") {
                Card(padding: 20) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("STATUS COLOURS").font(.system(size: 12, weight: .semibold)).tracking(0.6).foregroundStyle(theme.textMuted)
                        Text("Priority dots, overdue, done and warnings").font(.system(size: 13)).foregroundStyle(theme.text400)
                        Picker("Status colours", selection: Binding(
                            get: { look.statusColors == "tailwind" ? "tailwind" : "catppuccin" },
                            set: { look.statusColors = $0; apply(look.theme) }
                        )) {
                            Text("Catppuccin").tag("catppuccin")
                            Text("Classic (Tailwind)").tag("tailwind")
                        }
                        .pickerStyle(.segmented).labelsHidden()
                    }
                }
            }
            Card(padding: 20) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("CUSTOM THEME").font(.system(size: 12, weight: .semibold)).tracking(0.6).foregroundStyle(theme.textMuted)
                    ColorPicker(selection: Binding(
                        get: { Color(hex: look.customAccent) },
                        set: { look.customAccent = $0.hexString }
                    ), supportsOpacity: false) {
                        HStack {
                            Text("Accent colour").font(.system(size: 14, weight: .medium)).foregroundStyle(theme.text200)
                            Text(look.customAccent).font(.system(size: 12, design: .monospaced)).foregroundStyle(theme.textMuted)
                        }
                    }
                    Picker("Base", selection: $look.customBase) {
                        Text("Dark base").tag("dark")
                        Text("Light base").tag("light")
                    }
                    .pickerStyle(.segmented).labelsHidden()
                    PrimaryButton(title: look.theme == "custom" ? "Save custom theme" : "Use custom theme", fullWidth: true) {
                        apply("custom")
                    }
                }
            }
        }
    }

    private func tile(_ t: Theme, id: String) -> some View {
        let active = look.theme == id
        return Button { apply(id) } label: {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .topLeading) {
                    t.page
                    RoundedRectangle(cornerRadius: 4).fill(t.surface)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(t.border1, lineWidth: 1))
                        .padding(8)
                    Capsule().fill(t.accent).frame(width: 34, height: 6).padding(.leading, 16).padding(.top, 16)
                }
                .frame(height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                VStack(alignment: .leading, spacing: 1) {
                    Text(Theme.labels[id]?.label ?? id).font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.text100)
                    Text(Theme.labels[id]?.desc ?? "").font(.system(size: 11)).foregroundStyle(theme.textMuted)
                }
            }
            .padding(8)
            .background(theme.elevated.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(active ? theme.accent : theme.border1, lineWidth: active ? 2 : 1))
        }
        .buttonStyle(PressableStyle())
    }

    private func apply(_ id: String) {
        look.theme = id
        toast.run {
            try await APIClient.shared.post("/settings/appearance", [
                "theme": id, "customAccent": look.customAccent, "customBase": look.customBase,
                "statusColors": look.statusColors == "tailwind" ? "tailwind" : "catppuccin",
            ], method: "PUT")
            try? await app.loadMe() // re-themes the app
        }
    }
}

// ── Dashboard ────────────────────────────────────────────────────────────────

private struct DashboardTab: View {
    @Environment(AppState.self) private var app
    @Environment(Toast.self) private var toast
    @Environment(\.theme) private var theme
    @Binding var widgets: [SettingsData.Widget]

    var body: some View {
        List {
            Section {
                ForEach($widgets) { $w in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(w.label).foregroundStyle(w.enabled ? theme.text100 : theme.textMuted)
                            Text(w.description).font(.caption).foregroundStyle(theme.textMuted)
                        }
                        Spacer()
                        Toggle("", isOn: $w.enabled).labelsHidden().tint(theme.accent)
                            .onChange(of: w.enabled) { save() }
                    }
                    .listRowBackground(theme.surface)
                }
                .onMove { from, to in
                    widgets.move(fromOffsets: from, toOffset: to)
                    save()
                }
            } header: {
                Text("Today page").foregroundStyle(theme.textMuted)
            } footer: {
                Text("Choose which cards show on Today and drag to change their order. Quick Capture always stays at the bottom.")
                    .foregroundStyle(theme.textMuted)
            }
        }
        .alwaysEditing()
        .scrollContentBackground(.hidden)
        .contentMargins(.bottom, 80)
    }

    private func save() {
        let body = widgets.map { ["key": $0.key, "enabled": $0.enabled] as [String: Any] }
        toast.run {
            try await APIClient.shared.post("/settings/dashboard", ["widgets": body], method: "PUT")
            app.dataChanged() // Today reloads in the new order
        }
    }
}

// ── Data ─────────────────────────────────────────────────────────────────────
// views/settings/index.ejs "Data": exports (saved through the share sheet — Files, AirDrop…),
// imports (picked from Files), and deleting the account.

private struct DataTab: View {
    @Environment(AppState.self) private var app
    @Environment(Toast.self) private var toast
    @Environment(\.theme) private var theme

    private struct Export: Identifiable { let name: String; let title: String; let desc: String; var id: String { name } }
    private static let exports = [
        Export(name: "json", title: "Full data export", desc: "Everything — notes, tasks, reminders, routines, lists, bookmarks (JSON)"),
        Export(name: "tasks.csv", title: "Tasks", desc: "Title, status, priority, due date, tags, notes (CSV)"),
        Export(name: "notes.json", title: "Notes", desc: "All notes with markdown content, tags and metadata (JSON)"),
        Export(name: "bookmarks.csv", title: "Bookmarks (CSV)", desc: "Spreadsheet-friendly"),
        Export(name: "bookmarks.html", title: "Bookmarks (HTML)", desc: "Import into any browser"),
    ]

    private enum ImportKind: String, Identifiable {
        case notes, tasks, json
        var id: String { rawValue }
        var types: [UTType] {
            switch self {
            case .notes: [UTType(filenameExtension: "md") ?? .plainText, .plainText]
            case .tasks: [.commaSeparatedText]
            case .json: [.json]
            }
        }
        var ext: String { switch self { case .notes: "md"; case .tasks: "csv"; case .json: "json" } }
        var mime: String { switch self { case .notes: "text/markdown"; case .tasks: "text/csv"; case .json: "application/json" } }
    }

    @State private var exporting: String?
    @State private var shareURL: URL?
    @State private var importing: ImportKind?
    @State private var importBusy: ImportKind?
    @State private var importResult: String?
    @State private var importError: String?
    @State private var confirmUsername = ""
    @State private var confirmDelete = false
    @State private var deleting = false

    var body: some View {
        Page {
            Card {
                CardHeader(title: "Export your data")
                Text("Your data belongs to you. Download it anytime in open formats.")
                    .font(.system(size: 12)).foregroundStyle(theme.textMuted)
                    .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 4)
                ForEach(Array(Self.exports.enumerated()), id: \.element.id) { i, e in
                    if i > 0 { RowDivider() }
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(e.title).font(.system(size: 14, weight: .medium)).foregroundStyle(theme.text200)
                            Text(e.desc).font(.system(size: 12)).foregroundStyle(theme.textMuted)
                        }
                        Spacer()
                        if exporting == e.name {
                            ProgressView().frame(width: 72)
                        } else {
                            SecondaryButton(title: "Export", systemImage: "square.and.arrow.up") { export(e) }
                        }
                    }
                    .padding(.horizontal, 20).padding(.vertical, 12)
                }
            }

            Card {
                CardHeader(title: "Import data")
                VStack(alignment: .leading, spacing: 4) {
                    Text("Migrate from other tools or restore a previous export.").font(.system(size: 12)).foregroundStyle(theme.textMuted)
                    if let importResult { Banner(kind: .success, text: importResult).padding(.top, 8) }
                    if let importError { Banner(kind: .error, text: importError).padding(.top, 8) }
                }
                .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 4)
                importRow(.notes, "Notes from Markdown", "One or more .md files. Front matter title and tags are used if present.")
                RowDivider()
                importRow(.tasks, "Tasks from CSV", "Columns like Title, Status, Priority, Due Date, Tags, Notes (other names are recognised too).")
                RowDivider()
                importRow(.json, "Restore from JSON export", "A full export from Obelo. Anything already in your account is skipped, so it's safe to run twice.")
            }

            Card {
                CardHeader(title: "Delete account")
                VStack(alignment: .leading, spacing: 12) {
                    Text("Permanently deletes your account and everything in it — notes, tasks, reminders, routines, lists, bookmarks, calendars and uploads. This can't be undone. Export your data first if you want a copy.")
                        .font(.system(size: 13)).foregroundStyle(theme.text400)
                    Text("Type your username (@\(app.me?.user.username ?? "")) to confirm:").font(.system(size: 12)).foregroundStyle(theme.textMuted)
                    ThemedField(placeholder: app.me?.user.username ?? "username", text: $confirmUsername)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button { confirmDelete = true } label: {
                        HStack(spacing: 6) {
                            if deleting { ProgressView().tint(theme.onStatusFill).controlSize(.small) } else { Image(systemName: "trash") }
                            Text("Delete my account").font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundStyle(theme.onStatusFill).frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(theme.red700, in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(PressableStyle())
                    .disabled(confirmUsername != app.me?.user.username || deleting)
                    .opacity(confirmUsername == app.me?.user.username ? 1 : 0.4)
                }
                .padding(20)
            }
        }
        #if os(iOS)
        .sheet(item: Binding(get: { shareURL.map(ShareFile.init) }, set: { if $0 == nil { shareURL = nil } })) { file in
            ActivityView(items: [file.url]).ignoresSafeArea()
        }
        #else
        // The Mac saves an export with the usual Save panel
        .onChange(of: shareURL) { _, url in
            guard let url else { return }
            shareURL = nil
            let panel = NSSavePanel()
            panel.nameFieldStringValue = url.lastPathComponent
            panel.begin { response in
                guard response == .OK, let dest = panel.url else { return }
                try? FileManager.default.removeItem(at: dest)
                do { try FileManager.default.copyItem(at: url, to: dest) }
                catch { toast.show(error.localizedDescription, error: true) }
            }
        }
        #endif
        .fileImporter(isPresented: Binding(get: { importing != nil }, set: { if !$0 { importing = nil } }),
                      allowedContentTypes: importing?.types ?? [.data],
                      allowsMultipleSelection: importing == .notes) { result in
            let kind = importing
            importing = nil
            guard let kind else { return }
            switch result {
            case .success(let urls): runImport(kind, urls)
            case .failure(let error): importError = error.localizedDescription
            }
        }
        .confirmationDialog("Delete your Obelo account?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete everything", role: .destructive) { deleteAccount() }
        } message: {
            Text("Everything in your account is deleted permanently. This can't be undone.")
        }
    }

    private func importRow(_ kind: ImportKind, _ title: String, _ desc: String) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .medium)).foregroundStyle(theme.text200)
                Text(desc).font(.system(size: 12)).foregroundStyle(theme.textMuted)
            }
            Spacer()
            if importBusy == kind {
                ProgressView().frame(width: 72)
            } else {
                SecondaryButton(title: "Choose", systemImage: "folder") {
                    importResult = nil; importError = nil
                    importing = kind
                }
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
    }

    private func export(_ e: Export) {
        exporting = e.name
        Task {
            defer { exporting = nil }
            do {
                let data = try await APIClient.shared.data(path: "/api/v1/settings/export/\(e.name)")
                let ext = e.name == "json" ? "json" : (e.name as NSString).pathExtension
                let base = e.name == "json" ? "export" : (e.name as NSString).deletingPathExtension
                let url = FileManager.default.temporaryDirectory.appending(path: "obelo-\(base)-\(Fmt.ymd(.now)).\(ext)")
                try data.write(to: url, options: .atomic)
                shareURL = url
            } catch {
                toast.show(error.localizedDescription, error: true)
            }
        }
    }

    private func runImport(_ kind: ImportKind, _ urls: [URL]) {
        importBusy = kind
        Task {
            defer { importBusy = nil }
            var files: [APIClient.UploadFile] = []
            for url in urls {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                guard let data = try? Data(contentsOf: url) else { continue }
                // The server goes by extension (.md/.csv/.json), so make sure the name has the right one
                var name = url.lastPathComponent
                if (name as NSString).pathExtension.lowercased() != kind.ext { name += ".\(kind.ext)" }
                files.append(APIClient.UploadFile(data: data, filename: name, mimeType: kind.mime))
            }
            guard !files.isEmpty else { importError = "Couldn't read that file."; return }
            do {
                struct R: Decodable { let message: String }
                let r: R = try await APIClient.shared.upload("/settings/import/\(kind.rawValue)",
                                                            field: kind == .notes ? "files" : "file", files: files)
                importResult = r.message
                app.dataChanged()
            } catch {
                importError = error.localizedDescription
            }
        }
    }

    private func deleteAccount() {
        deleting = true
        Task {
            defer { deleting = false }
            do {
                try await APIClient.shared.post("/settings/delete-account", ["confirmUsername": confirmUsername])
                APIClient.shared.clearCookies()
                await app.signOut()
            } catch {
                toast.show(error.localizedDescription, error: true)
            }
        }
    }
}

private struct ShareFile: Identifiable { let url: URL; var id: URL { url } }

#if os(iOS)
/// The system share sheet for a file (Save to Files, AirDrop, Mail…)
private struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
#endif

// ── Avatar ───────────────────────────────────────────────────────────────────

/// Profile photo: the custom upload (auth-gated) or Gravatar, else the initial like the web
struct AvatarView: View {
    @Environment(\.theme) private var theme
    let url: String?
    let name: String
    var size: CGFloat = 28
    @State private var image: PlatformImage?

    private static var version = 0
    static func bustCache() { version += 1 }

    var body: some View {
        ZStack {
            if let image {
                Image(platformImage: image).resizable().scaledToFill()
            } else {
                Text(String(name.prefix(1)).uppercased())
                    .font(.system(size: size * 0.43, weight: .semibold)).foregroundStyle(theme.onAccent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(theme.accentDark)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .task(id: "\(url ?? "")|\(Self.version)") { await load() }
    }

    private func load() async {
        guard let url, !url.isEmpty else { image = nil; return }
        if url.hasPrefix("/") {
            image = (try? await APIClient.shared.data(path: url)).flatMap(PlatformImage.init(data:))
        } else if let remote = URL(string: url.replacingOccurrences(of: "s=80", with: "s=160")),
                  let (d, _) = try? await URLSession.shared.data(from: remote) {
            image = PlatformImage(data: d)
        }
    }
}

extension Color {
    /// "#rrggbb" for the custom accent
    var hexString: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        #if os(iOS)
        let c = UIColor(self).resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        #else
        NSAppearance(named: .darkAqua)?.performAsCurrentDrawingAppearance {
            (NSColor(self).usingColorSpace(.sRGB) ?? .black).getRed(&r, green: &g, blue: &b, alpha: &a)
        }
        #endif
        let clamp = { (v: CGFloat) in Int((min(1, max(0, v)) * 255).rounded()) }
        return String(format: "#%02x%02x%02x", clamp(r), clamp(g), clamp(b))
    }
}
