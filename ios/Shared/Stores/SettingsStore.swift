import Foundation
import SwiftUI

// The Settings window's logic, with no interface. `SettingsStore` holds your account, password, devices, modules,
// appearance and dashboard; the other stores below each hold one more tab. Every one talks to the server through
// `SettingsAPI`, so tests can use a stub. Changes stay in a working copy until a card's Save is pressed.

@MainActor @Observable
final class SettingsStore {
    private let api: SettingsAPI

    private(set) var data: SettingsData?
    private(set) var loaded = false
    var notice: SettingsNotice?

    init(api: SettingsAPI) { self.api = api }
    convenience init() { self.init(api: LiveSettingsAPI()) }

    // The working copies, one per card
    var account = AccountDraft()
    private(set) var modules: [SettingsData.Module] = []
    var look = SettingsData.Look(theme: "dark", customAccent: "#6366f1", customBase: "dark", statusColors: "catppuccin")
    private(set) var widgets: [SettingsData.Widget] = []
    private(set) var sessions: [DeviceSession] = []
    var password = PasswordDraft()

    struct AccountDraft: Equatable {
        var displayName = ""
        var email = ""
        var timezone = "America/New_York"
        var timeFormat = "12h"
    }

    struct PasswordDraft: Equatable {
        var current = ""
        var new = ""
        var again = ""
    }

    private func say(_ text: String, error: Bool = false) { notice = SettingsNotice(text: text, isError: error) }

    // ── Loading ─────────────────────────────────────────────────────────────

    func load() async {
        do {
            let d = try await api.settings()
            data = d; loaded = true
            account = AccountDraft(displayName: d.account.displayName, email: d.account.email, timezone: d.account.timezone, timeFormat: d.account.timeFormat)
            modules = d.modules
            look = d.appearance
            widgets = d.dashboard
        } catch { say(error.localizedDescription, error: true) }
        await loadSessions()
    }

    func loadSessions() async {
        if let s = try? await api.sessions() { sessions = s }
    }

    // ── Account ─────────────────────────────────────────────────────────────

    var isAccountDirty: Bool {
        guard let a = data?.account else { return false }
        return account != AccountDraft(displayName: a.displayName, email: a.email, timezone: a.timezone, timeFormat: a.timeFormat)
    }

    @discardableResult
    func saveAccount() async -> Bool {
        do {
            try await api.saveAccount(displayName: account.displayName, email: account.email, timezone: account.timezone, timeFormat: account.timeFormat)
            data?.account.displayName = account.displayName.trimmingCharacters(in: .whitespaces).isEmpty ? (data?.account.displayName ?? "") : account.displayName
            data?.account.email = account.email; data?.account.timezone = account.timezone; data?.account.timeFormat = account.timeFormat
            say("Account updated")
            return true
        } catch { say(error.localizedDescription, error: true); return false }
    }

    func uploadAvatar(_ jpeg: Data) async {
        do { try await api.uploadAvatar(jpeg, filename: "avatar.jpg"); say("Avatar updated"); await load() }
        catch { say(error.localizedDescription, error: true) }
    }

    func removeAvatar() async {
        do { try await api.removeAvatar(); say("Avatar removed"); await load() }
        catch { say(error.localizedDescription, error: true) }
    }

    // ── Password ────────────────────────────────────────────────────────────

    var hasPassword: Bool { data?.account.hasPassword ?? false }
    /// Only when the server allows password sign-in
    var offersPassword: Bool { data?.account.passwordLogin ?? false }

    /// What is wrong with the password card before asking the server, or nil
    var passwordProblem: String? {
        if password.new.isEmpty { return nil }
        if password.new != password.again { return "The two new passwords don't match" }
        return nil
    }

    var canSavePassword: Bool {
        !password.new.isEmpty && !password.again.isEmpty && passwordProblem == nil && (!hasPassword || !password.current.isEmpty)
    }

    @discardableResult
    func savePassword() async -> Bool {
        if let problem = passwordProblem { say(problem, error: true); return false }
        do {
            try await api.changePassword(current: password.current, new: password.new)
            password = PasswordDraft()
            data?.account.hasPassword = true
            say("Password saved")
            await loadSessions()
            return true
        } catch { say(error.localizedDescription, error: true); return false }
    }

    // ── Devices ─────────────────────────────────────────────────────────────

    var otherSessions: [DeviceSession] { sessions.filter { !$0.current } }

    func endSession(_ key: String) async {
        do { try await api.endSession(key: key); sessions.removeAll { $0.key == key } }
        catch { say(error.localizedDescription, error: true) }
    }

    func endOtherSessions() async {
        do {
            let n = try await api.endOtherSessions()
            say("Signed out \(n) device\(n == 1 ? "" : "s")")
            sessions.removeAll { !$0.current }
        } catch { say(error.localizedDescription, error: true) }
    }

    static func endOthersQuestion(_ n: Int) -> String { "Sign out \(n) other device\(n == 1 ? "" : "s")? You'll stay signed in here." }

    // ── Modules ─────────────────────────────────────────────────────────────

    var isModulesDirty: Bool { modules != data?.modules }

    func toggleModule(_ key: String) {
        guard let i = modules.firstIndex(where: { $0.key == key }), !modules[i].alwaysEnabled else { return }
        modules[i].enabled.toggle()
    }

    @discardableResult
    func saveModules() async -> Bool {
        do {
            try await api.saveModules(modules.map { ($0.key, $0.enabled) })
            data?.modules = modules
            say("Modules saved")
            return true
        } catch { say(error.localizedDescription, error: true); return false }
    }

    func revertModules() { modules = data?.modules ?? modules }

    // ── Appearance ──────────────────────────────────────────────────────────

    var isAppearanceDirty: Bool {
        guard let a = data?.appearance else { return false }
        return look.theme != a.theme || look.customAccent != a.customAccent || look.customBase != a.customBase || look.statusColors != a.statusColors
    }

    /// The saved look, for putting the app's colours back when the window closes without saving
    var savedLook: SettingsData.Look? { data?.appearance }

    static func isValidAccent(_ hex: String) -> Bool {
        hex.range(of: "^#[0-9a-fA-F]{6}$", options: .regularExpression) != nil
    }

    @discardableResult
    func saveAppearance() async -> Bool {
        guard Self.isValidAccent(look.customAccent) else { say("Pick an accent colour", error: true); return false }
        do {
            try await api.saveAppearance(theme: look.theme, customAccent: look.customAccent, customBase: look.customBase,
                                         statusColors: look.statusColors == "tailwind" ? "tailwind" : "catppuccin")
            data?.appearance = look
            say("Appearance saved")
            return true
        } catch { say(error.localizedDescription, error: true); return false }
    }

    func revertAppearance() { if let a = data?.appearance { look = a } }

    // ── Dashboard ───────────────────────────────────────────────────────────

    var isDashboardDirty: Bool { widgets != data?.dashboard }

    func toggleWidget(_ key: String) {
        guard let i = widgets.firstIndex(where: { $0.key == key }) else { return }
        widgets[i].enabled.toggle()
    }

    func moveWidget(_ key: String, by offset: Int) {
        guard let from = widgets.firstIndex(where: { $0.key == key }) else { return }
        let to = min(max(from + offset, 0), widgets.count - 1)
        guard to != from else { return }
        widgets.insert(widgets.remove(at: from), at: to)
    }

    func moveWidget(_ key: String, to target: String) {
        guard let from = widgets.firstIndex(where: { $0.key == key }), let to = widgets.firstIndex(where: { $0.key == target }) else { return }
        moveWidget(key, by: to - from)
    }

    @discardableResult
    func saveDashboard() async -> Bool {
        do {
            try await api.saveDashboard(widgets.map { ($0.key, $0.enabled) })
            data?.dashboard = widgets
            say("Dashboard saved")
            return true
        } catch { say(error.localizedDescription, error: true); return false }
    }

    // ── Delete account ──────────────────────────────────────────────────────

    /// The typed name must be your username, as on the web
    func canDeleteAccount(typed: String) -> Bool { !typed.isEmpty && typed == data?.account.username }

    /// True when the account was deleted (the caller then signs out)
    func deleteAccount(typed: String) async -> Bool {
        guard canDeleteAccount(typed: typed) else { say("Type your username to confirm", error: true); return false }
        do { try await api.deleteAccount(confirmUsername: typed); return true }
        catch { say(error.localizedDescription, error: true); return false }
    }
}

// MARK: - Notifications

@MainActor @Observable
final class NotificationSettingsStore {
    private let api: SettingsAPI
    private(set) var settings: NotificationSettings?
    private var saved: NotificationSettings?
    var notice: SettingsNotice?

    /// The three kinds you can switch on, with the web's wording
    static let types: [(key: String, label: String, detail: String, timed: Bool)] = [
        ("daily_digest", "Daily morning digest", "Today's calendar events and top tasks", true),
        ("slipping_tasks", "Slipping tasks alert", "Monday morning summary of overdue tasks", true),
        ("task_due", "Task & reminder alerts", "15 min before, at the due time, and when overdue — for any task or reminder with a set time", false),
    ]

    init(api: SettingsAPI) { self.api = api }
    convenience init() { self.init(api: LiveSettingsAPI()) }

    private func say(_ text: String, error: Bool = false) { notice = SettingsNotice(text: text, isError: error) }

    /// Edits are made to this copy
    var draft: NotificationSettings? {
        get { settings }
        set { settings = newValue }
    }

    var isDirty: Bool {
        guard let s = settings, let o = saved else { return false }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys   // a dictionary's order must not make two equal copies look different
        return (try? encoder.encode(s)) != (try? encoder.encode(o))
    }

    func load() async {
        do { let s = try await api.notifications(); settings = s; saved = s }
        catch { say(error.localizedDescription, error: true) }
    }

    func setType(_ key: String, _ change: (inout NotificationSettings.TypePref) -> Void) {
        guard var pref = settings?.types[key] else { return }
        change(&pref)
        settings?.types[key] = pref
    }

    @discardableResult
    func save() async -> Bool {
        guard let s = settings else { return false }
        do { try await api.saveNotifications(s); say("Notification settings saved"); await load(); return true }
        catch { say(error.localizedDescription, error: true); return false }
    }

    /// "ntfy" or "email". Unsaved changes are saved first by the person, as the web needs.
    func test(_ which: String) async {
        if isDirty { say("Save your changes first", error: true); return }
        do { say(try await api.testNotification("test-\(which)")) }
        catch { say(error.localizedDescription, error: true) }
    }

    func newTopic() async {
        do {
            let topic = try await api.newNtfyTopic()
            settings?.ntfyTopic = topic; saved?.ntfyTopic = topic
            say("New topic created — subscribe to it in the ntfy app")
        } catch { say(error.localizedDescription, error: true) }
    }

    static let ntfyNotConfigured = "ntfy isn't set up on this server. Ask the server admin to turn it on."
}

// MARK: - Notes

@MainActor @Observable
final class NoteSettingsStore {
    private let api: SettingsAPI
    private(set) var prefs: NotesPrefs?
    private var saved: NotesPrefs?
    var notice: SettingsNotice?

    static let papers: [(value: String, label: String, detail: String)] = [
        ("theme", "Match theme", "Dark paper in dark themes, light paper in light themes"),
        ("dark", "Dark", "Always dark paper with light ink"),
        ("white", "White", "Always white paper with dark ink"),
    ]
    static let autosaveChoices: [(value: String, label: String, detail: String)] = [
        ("immediate", "Immediate", "1.5 seconds after last change"),
        ("2min", "2 minutes", "after last change"),
        ("5min", "5 minutes", "after last change"),
    ]

    init(api: SettingsAPI) { self.api = api }
    convenience init() { self.init(api: LiveSettingsAPI()) }

    private func say(_ text: String, error: Bool = false) { notice = SettingsNotice(text: text, isError: error) }

    func load() async {
        do { let p = try await api.notesPrefs(); prefs = p; saved = p }
        catch { say(error.localizedDescription, error: true) }
    }

    func setAutosave(enabled: Bool) { prefs?.autosaveEnabled = enabled }
    func setAutosave(duration: String) { prefs?.autosaveDuration = duration }
    func setPaper(_ paper: String) { prefs?.notePaper = paper }

    var isDirty: Bool { prefs != saved }

    @discardableResult
    func save() async -> Bool {
        guard let p = prefs else { return false }
        do { try await api.saveNotesPrefs(p); saved = p; say("Notes settings saved"); return true }
        catch { say(error.localizedDescription, error: true); return false }
    }

    // ── Note Lock PIN ───────────────────────────────────────────────────────

    var hasPin: Bool { prefs?.hasPin ?? false }

    /// 4 to 6 digits, typed twice the same, and the current one when changing it
    func pinProblem(current: String, new: String, confirm: String) -> String? {
        let digits = { (s: String) in s.allSatisfy(\.isNumber) && (4...6).contains(s.count) }
        if hasPin && !digits(current) { return "Enter your current PIN" }
        if !digits(new) { return "The PIN must be 4 to 6 digits" }
        if new != confirm { return "The two PINs don't match" }
        return nil
    }

    @discardableResult
    func setPin(current: String, new: String, confirm: String) async -> Bool {
        if let problem = pinProblem(current: current, new: new, confirm: confirm) { say(problem, error: true); return false }
        do { say(try await api.setPin(current: current, new: new, confirm: confirm)); await load(); return true }
        catch { say(error.localizedDescription, error: true); return false }
    }

    @discardableResult
    func removePin(current: String) async -> Bool {
        guard !current.isEmpty else { say("Enter your current PIN", error: true); return false }
        do { say(try await api.removePin(current: current)); await load(); return true }
        catch { say(error.localizedDescription, error: true); return false }
    }
}

// MARK: - Tags

@MainActor @Observable
final class TagManagerStore {
    private let api: SettingsAPI
    private(set) var tags: [SettingsTag] = []
    private(set) var loaded = false
    var notice: SettingsNotice?

    init(api: SettingsAPI) { self.api = api }
    convenience init() { self.init(api: LiveSettingsAPI()) }

    private func say(_ text: String, error: Bool = false) { notice = SettingsNotice(text: text, isError: error) }
    private static func clean(_ s: String) -> String { s.trimmingCharacters(in: .whitespaces).lowercased() }

    func load() async {
        do { tags = try await api.tags().sorted { $0.name < $1.name }; loaded = true }
        catch { say(error.localizedDescription, error: true) }
    }

    @discardableResult
    func create(_ name: String) async -> Bool {
        let n = Self.clean(name).trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard !n.isEmpty else { return false }
        do { try await api.createTag(n); say("#\(n) created"); await load(); return true }
        catch { say(error.localizedDescription, error: true); return false }
    }

    @discardableResult
    func rename(_ tag: SettingsTag, to name: String) async -> Bool {
        let n = Self.clean(name).trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard !n.isEmpty, n != tag.name else { return false }
        do { try await api.renameTag(from: tag.name, to: n); say("#\(tag.name) renamed to #\(n)"); await load(); return true }
        catch { say(error.localizedDescription, error: true); return false }
    }

    @discardableResult
    func delete(_ tag: SettingsTag) async -> Bool {
        do { try await api.deleteTag(tag.name); say("#\(tag.name) deleted from all items"); await load(); return true }
        catch { say(error.localizedDescription, error: true); return false }
    }

    static func deleteQuestion(_ tag: SettingsTag) -> String {
        "Delete tag \"\(tag.name)\" from all \(tag.count) item\(tag.count == 1 ? "" : "s")?"
    }
}

// MARK: - Data

struct ExportedFile: Equatable {
    let filename: String
    let data: Data
}

@MainActor @Observable
final class DataTransferStore {
    private let api: SettingsAPI
    private(set) var busy: String?
    var notice: SettingsNotice?

    init(api: SettingsAPI) { self.api = api }
    convenience init() { self.init(api: LiveSettingsAPI()) }

    private func say(_ text: String, error: Bool = false) { notice = SettingsNotice(text: text, isError: error) }

    /// Fetches an export from the server, named for today
    func export(_ kind: ExportKind, on day: String) async -> ExportedFile? {
        busy = kind.name
        defer { busy = nil }
        do { return ExportedFile(filename: kind.filename(on: day), data: try await api.export(kind.name)) }
        catch { say(error.localizedDescription, error: true); return nil }
    }

    /// Sends the chosen files and says what the server did ("Imported 12 notes")
    @discardableResult
    func importFiles(_ kind: ImportKind, _ picked: [(name: String, data: Data)]) async -> Bool {
        let files = picked.map { APIClient.UploadFile(data: $0.data, filename: kind.uploadName(for: $0.name), mimeType: kind.mime) }
        guard !files.isEmpty else { say("Couldn't read that file.", error: true); return false }
        busy = kind.rawValue
        defer { busy = nil }
        do { say(try await api.importFiles(kind, files)); return true }
        catch { say(error.localizedDescription, error: true); return false }
    }
}

// MARK: - API tokens (the Shortcuts tab)

@MainActor @Observable
final class ApiTokensStore {
    private let api: SettingsAPI
    private(set) var tokens: [ApiTokenItem] = []
    private(set) var loaded = false
    /// The token just made, shown once
    private(set) var fresh: ApiTokenItem?
    var label = ""
    var notice: SettingsNotice?

    init(api: SettingsAPI) { self.api = api }
    convenience init() { self.init(api: LiveSettingsAPI()) }

    private func say(_ text: String, error: Bool = false) { notice = SettingsNotice(text: text, isError: error) }

    func load() async {
        do { tokens = try await api.apiTokens(); loaded = true }
        catch { say(error.localizedDescription, error: true) }
    }

    /// Makes a token with the label in the box (the server names an empty one "iOS Shortcut")
    @discardableResult
    func create() async -> Bool {
        do {
            let t = try await api.createApiToken(label: label.trimmingCharacters(in: .whitespaces))
            fresh = t; label = ""
            await load()
            return true
        } catch { say(error.localizedDescription, error: true); return false }
    }

    func dismissFresh() { fresh = nil }

    func revoke(_ token: ApiTokenItem) async {
        do {
            try await api.revokeApiToken(id: token.id)
            if fresh?.id == token.id { fresh = nil }
            await load()
        } catch { say(error.localizedDescription, error: true) }
    }

    static let revokeQuestion = "Revoke this token? Any Shortcut using it will stop working."

    /// The web's "Capture from iOS Shortcuts" lines, with this server's address
    static func howTo(server: String) -> [String] {
        ["Send POST \(server)/capture/api with the header Authorization: Bearer <your-token> and the JSON body { \"raw\": \"call the dentist tuesday 3pm\" }.",
         "The response is a draft to confirm in the app."]
    }
}
