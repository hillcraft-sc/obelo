import Foundation
import SwiftUI

// Settings ▸ Calendars, with no interface: the connected accounts (CalDAV, and Google ones connected on the
// web), their calendars, your own shareable calendars with their members, and the default calendar for new
// events. Mirrors the web's Calendar Sources page. Talks to the server through `CalendarSourcesAPI` so tests
// can use a stub. The server never sends a password or token, so none is held here.

struct SourceCalendar: Codable, Equatable, Identifiable {
    let url: String
    let name: String
    let color: String?
    var selected: Bool
    var isFamily: Bool
    var id: String { url }
}

struct CalendarAccount: Codable, Equatable, Identifiable {
    let id: Int
    let type: String
    var name: String
    var color: String
    let active: Bool
    let lastSynced: Date?
    var isFamily: Bool
    var calendars: [SourceCalendar]

    var isGoogle: Bool { type == "google" }
    var kindLabel: String { isGoogle ? "Google Calendar" : "CalDAV" }
}

struct CalendarMember: Codable, Equatable, Identifiable {
    let userId: Int
    let username: String
    let displayName: String?
    let canEdit: Bool
    var id: Int { userId }
    var shownName: String { (displayName?.isEmpty == false ? displayName : nil) ?? username }
}

struct OwnCalendar: Codable, Equatable, Identifiable {
    let id: Int
    var name: String
    var color: String
    var members: [CalendarMember]
}

struct ShareableUser: Codable, Equatable, Identifiable {
    let id: Int
    let username: String
    let displayName: String?
}

struct CalendarSourcesOverview: Decodable, Equatable {
    var sources: [CalendarAccount]
    var localCalendars: [OwnCalendar]
    let shareableUsers: [ShareableUser]
    var defaultTarget: String
    let targets: [CalendarChoice]
    /// The server can connect Google accounts (the apps can't start that yet)
    let googleConfigured: Bool?
}

/// What the "Add account" form holds
struct CaldavDraft: Equatable {
    enum Provider: String, CaseIterable { case apple, other }
    var provider = Provider.apple
    var name = ""
    var username = ""
    var password = ""
    var serverUrl = ""
    var calendarHomeUrl = ""
    var color = "#6366f1"

    /// The same sentence the web page shows under the provider choice
    var hint: String {
        switch provider {
        case .apple: "Use your Apple ID and an app-specific password from appleid.apple.com, under Security."
        case .other: "Enter your server address and credentials. CalDAV servers include Nextcloud, Fastmail and Radicale."
        }
    }
    var usernamePlaceholder: String { provider == .apple ? "you@icloud.com" : "username" }

    var canSubmit: Bool {
        !username.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty
            && (provider == .apple || !serverUrl.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    var body: [String: Any] {
        ["provider": provider.rawValue, "name": name.trimmingCharacters(in: .whitespaces),
         "username": username.trimmingCharacters(in: .whitespaces), "password": password,
         "serverUrl": provider == .apple ? "https://caldav.icloud.com" : serverUrl.trimmingCharacters(in: .whitespaces),
         "calendarHomeUrl": provider == .apple ? "" : calendarHomeUrl.trimmingCharacters(in: .whitespaces),
         "color": color]
    }
}

struct ConnectResult: Decodable, Equatable {
    let found: Int
    let synced: Int?
    let syncError: String?
}

struct SyncResult: Decodable, Equatable { let count: Int; let name: String }
struct SelectResult: Decodable, Equatable { let selected: Int; let count: Int?; let syncError: String? }

@MainActor
protocol CalendarSourcesAPI {
    func overview() async throws -> CalendarSourcesOverview
    func connect(_ draft: CaldavDraft) async throws -> ConnectResult
    func sync(id: Int) async throws -> SyncResult
    func setColor(id: Int, _ color: String) async throws
    func remove(id: Int) async throws
    func setCalendars(id: Int, urls: [String]) async throws -> SelectResult
    func setFamily(id: Int, url: String?) async throws
    func setDefault(_ target: String) async throws
    func createLocal(name: String, color: String) async throws
    func updateLocal(id: Int, name: String, color: String) async throws
    func deleteLocal(id: Int) async throws
    func addMember(calendar: Int, username: String) async throws
    func removeMember(calendar: Int, userId: Int) async throws
}

@MainActor
struct LiveCalendarSourcesAPI: CalendarSourcesAPI {
    private var api: APIClient { .shared }

    func overview() async throws -> CalendarSourcesOverview { try await api.get("/calendar/sources") }
    func connect(_ d: CaldavDraft) async throws -> ConnectResult { try await api.post("/calendar/sources", d.body) }
    func sync(id: Int) async throws -> SyncResult { try await api.post("/calendar/sources/\(id)/sync") }
    func setColor(id: Int, _ color: String) async throws { try await api.post("/calendar/sources/\(id)", ["color": color], method: "PUT") }
    func remove(id: Int) async throws { try await api.delete("/calendar/sources/\(id)") }
    func setCalendars(id: Int, urls: [String]) async throws -> SelectResult {
        try await api.post("/calendar/sources/\(id)/calendars", ["urls": urls], method: "PUT")
    }
    func setFamily(id: Int, url: String?) async throws {
        try await api.post("/calendar/sources/\(id)/family", url.map { ["url": $0] } ?? [:], method: "PUT")
    }
    func setDefault(_ target: String) async throws { try await api.post("/calendar/default", ["target": target], method: "PUT") }
    func createLocal(name: String, color: String) async throws { try await api.post("/calendar/local", ["name": name, "color": color]) }
    func updateLocal(id: Int, name: String, color: String) async throws {
        try await api.post("/calendar/local/\(id)", ["name": name, "color": color], method: "PUT")
    }
    func deleteLocal(id: Int) async throws { try await api.delete("/calendar/local/\(id)") }
    func addMember(calendar: Int, username: String) async throws {
        try await api.post("/calendar/local/\(calendar)/members", ["username": username])
    }
    func removeMember(calendar: Int, userId: Int) async throws { try await api.delete("/calendar/local/\(calendar)/members/\(userId)") }
}

@MainActor @Observable
final class CalendarSourcesStore {
    private(set) var data: CalendarSourcesOverview?
    private(set) var loading = false
    /// A green line ("Connected! Found 2 calendars.") or a red one; both clear when the next thing starts
    private(set) var notice: String?
    private(set) var failure: String?
    /// Ids being synced right now
    private(set) var syncing: Set<Int> = []
    private let api: CalendarSourcesAPI

    init(api: CalendarSourcesAPI) { self.api = api }
    convenience init() { self.init(api: LiveCalendarSourcesAPI()) }

    var accounts: [CalendarAccount] { data?.sources ?? [] }
    var ownCalendars: [OwnCalendar] { data?.localCalendars ?? [] }
    var targets: [CalendarChoice] { data?.targets ?? [] }
    var defaultTarget: String { data?.defaultTarget ?? "local" }

    /// People you could add to a calendar: not you, and not already in it
    func peopleToAdd(to calendar: OwnCalendar) -> [ShareableUser] {
        let taken = Set(calendar.members.map(\.username))
        return (data?.shareableUsers ?? []).filter { !taken.contains($0.username) }
    }

    func load() async {
        loading = true
        defer { loading = false }
        do { data = try await api.overview() } catch { failure = error.localizedDescription }
    }

    /// Runs a change, reloads, and reports. `done` makes the success line from what the server answered.
    private func act<T>(_ work: () async throws -> T, done: ((T) -> String?)? = nil) async -> Bool {
        notice = nil; failure = nil
        do {
            let result = try await work()
            data = try await api.overview()
            notice = done?(result)
            return true
        } catch {
            failure = error.localizedDescription
            return false
        }
    }

    func dismissMessages() { notice = nil; failure = nil }

    // ── Accounts ────────────────────────────────────────────────────────────

    @discardableResult
    func connect(_ draft: CaldavDraft) async -> Bool {
        await act({ try await api.connect(draft) }, done: { r in
            var text = "Connected! Found \(r.found) calendar\(r.found == 1 ? "" : "s")."
            if let err = r.syncError { text += " \(err)" } else if let n = r.synced { text += " Synced \(n) event\(n == 1 ? "" : "s")." }
            return text
        })
    }

    func sync(_ account: CalendarAccount) async {
        syncing.insert(account.id)
        defer { syncing.remove(account.id) }
        _ = await act({ try await api.sync(id: account.id) }, done: { "Synced \($0.count) event\($0.count == 1 ? "" : "s") from \($0.name)." })
    }

    func setColor(_ account: CalendarAccount, _ color: String) async { _ = await act { try await api.setColor(id: account.id, color) } }
    func remove(_ account: CalendarAccount) async { _ = await act({ try await api.remove(id: account.id) }, done: { _ in "Removed \(account.name)." }) }

    /// Which of the account's calendars show (all of them when none is ticked, as on the web)
    func setCalendars(_ account: CalendarAccount, urls: [String]) async {
        _ = await act({ try await api.setCalendars(id: account.id, urls: urls) }, done: { r in
            if let err = r.syncError { return err }
            let n = r.count ?? 0
            return "Saved. Synced \(n) event\(n == 1 ? "" : "s") from \(r.selected == 0 ? "all" : String(r.selected)) calendar\(r.selected == 1 ? "" : "s")."
        })
    }

    /// The family calendar: one calendar in this account, or none
    func setFamily(_ account: CalendarAccount, url: String?) async { _ = await act { try await api.setFamily(id: account.id, url: url) } }

    func setDefault(_ target: String) async { _ = await act { try await api.setDefault(target) } }

    // ── Your own calendars ──────────────────────────────────────────────────

    @discardableResult
    func createOwn(name: String, color: String) async -> Bool {
        let clean = name.trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty else { failure = "Name is required."; return false }
        return await act { try await api.createLocal(name: clean, color: color) }
    }

    func updateOwn(_ calendar: OwnCalendar, name: String, color: String) async {
        let clean = name.trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty else { failure = "Name is required."; return }
        _ = await act { try await api.updateLocal(id: calendar.id, name: clean, color: color) }
    }

    /// Its events stay (they just lose the calendar), as on the web
    func deleteOwn(_ calendar: OwnCalendar) async { _ = await act { try await api.deleteLocal(id: calendar.id) } }

    @discardableResult
    func addMember(_ calendar: OwnCalendar, username: String) async -> Bool {
        let who = username.trimmingCharacters(in: .whitespaces)
        guard !who.isEmpty else { return false }
        return await act({ try await api.addMember(calendar: calendar.id, username: who) }, done: { _ in "\(who) added to \"\(calendar.name)\"." })
    }

    func removeMember(_ calendar: OwnCalendar, _ member: CalendarMember) async {
        _ = await act { try await api.removeMember(calendar: calendar.id, userId: member.userId) }
    }
}
