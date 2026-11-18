import Foundation

// Every call the Settings screens make, behind one protocol so the stores can be tested with a stub.

@MainActor
protocol SettingsAPI {
    func settings() async throws -> SettingsData
    func saveAccount(displayName: String, email: String, timezone: String, timeFormat: String) async throws
    func changePassword(current: String, new: String) async throws
    func sessions() async throws -> [DeviceSession]
    func endSession(key: String) async throws
    func endOtherSessions() async throws -> Int
    func uploadAvatar(_ data: Data, filename: String) async throws
    func removeAvatar() async throws
    func saveModules(_ list: [(key: String, enabled: Bool)]) async throws
    func saveAppearance(theme: String, customAccent: String, customBase: String, statusColors: String) async throws
    func saveDashboard(_ list: [(key: String, enabled: Bool)]) async throws
    func deleteAccount(confirmUsername: String) async throws
    func notifications() async throws -> NotificationSettings
    func saveNotifications(_ s: NotificationSettings) async throws
    func testNotification(_ which: String) async throws -> String
    func newNtfyTopic() async throws -> String
    func notesPrefs() async throws -> NotesPrefs
    func saveNotesPrefs(_ p: NotesPrefs) async throws
    func setPin(current: String, new: String, confirm: String) async throws -> String
    func removePin(current: String) async throws -> String
    func tags() async throws -> [SettingsTag]
    func createTag(_ name: String) async throws
    func renameTag(from old: String, to new: String) async throws
    func deleteTag(_ name: String) async throws
    func export(_ name: String) async throws -> Data
    func importFiles(_ kind: ImportKind, _ files: [APIClient.UploadFile]) async throws -> String
    func apiTokens() async throws -> [ApiTokenItem]
    func createApiToken(label: String) async throws -> ApiTokenItem
    func revokeApiToken(id: Int) async throws
}

@MainActor
struct LiveSettingsAPI: SettingsAPI {
    private var api: APIClient { .shared }
    private struct Sessions: Decodable { let sessions: [DeviceSession] }
    private struct Ended: Decodable { let ended: Int }
    private struct Message: Decodable { let message: String }
    private struct Topic: Decodable { let ntfyTopic: String }
    private struct Tags: Decodable { let tags: [SettingsTag] }
    private struct Tokens: Decodable { let tokens: [ApiTokenItem] }

    func settings() async throws -> SettingsData { try await api.get("/settings") }
    func saveAccount(displayName: String, email: String, timezone: String, timeFormat: String) async throws {
        try await api.post("/settings/account", ["displayName": displayName, "email": email, "timezone": timezone, "timeFormat": timeFormat], method: "PUT")
    }
    func changePassword(current: String, new: String) async throws {
        try await api.post("/settings/password", ["currentPassword": current, "newPassword": new])
    }
    func sessions() async throws -> [DeviceSession] { (try await api.get("/sessions") as Sessions).sessions }
    func endSession(key: String) async throws { try await api.post("/sessions/\(key)/end") }
    func endOtherSessions() async throws -> Int { (try await api.post("/sessions/end-others") as Ended).ended }
    func uploadAvatar(_ data: Data, filename: String) async throws {
        let _: EmptyResponse = try await api.upload("/settings/avatar", field: "avatar", data: data, filename: filename, mimeType: "image/jpeg")
    }
    func removeAvatar() async throws { try await api.delete("/settings/avatar") }
    func saveModules(_ list: [(key: String, enabled: Bool)]) async throws {
        try await api.post("/settings/modules", ["modules": list.map { ["key": $0.key, "enabled": $0.enabled] as [String: Any] }], method: "PUT")
    }
    func saveAppearance(theme: String, customAccent: String, customBase: String, statusColors: String) async throws {
        try await api.post("/settings/appearance", ["theme": theme, "customAccent": customAccent, "customBase": customBase, "statusColors": statusColors], method: "PUT")
    }
    func saveDashboard(_ list: [(key: String, enabled: Bool)]) async throws {
        try await api.post("/settings/dashboard", ["widgets": list.map { ["key": $0.key, "enabled": $0.enabled] as [String: Any] }], method: "PUT")
    }
    func deleteAccount(confirmUsername: String) async throws { try await api.post("/settings/delete-account", ["confirmUsername": confirmUsername]) }
    func notifications() async throws -> NotificationSettings { try await api.get("/settings/notifications") }
    func saveNotifications(_ s: NotificationSettings) async throws {
        let body = try JSONSerialization.jsonObject(with: JSONEncoder().encode(s)) as? [String: Any] ?? [:]
        try await api.post("/settings/notifications", body, method: "PUT")
    }
    func testNotification(_ which: String) async throws -> String { (try await api.post("/settings/notifications/\(which)") as Message).message }
    func newNtfyTopic() async throws -> String { (try await api.post("/settings/notifications/ntfy-topic") as Topic).ntfyTopic }
    func notesPrefs() async throws -> NotesPrefs { try await api.get("/settings/notes") }
    func saveNotesPrefs(_ p: NotesPrefs) async throws {
        var body: [String: Any] = ["autosaveEnabled": p.autosaveEnabled, "autosaveDuration": p.autosaveDuration]
        if let paper = p.notePaper { body["notePaper"] = paper }
        try await api.post("/settings/notes", body, method: "PUT")
    }
    func setPin(current: String, new: String, confirm: String) async throws -> String {
        (try await api.post("/settings/note-pin", ["currentPin": current, "newPin": new, "confirmPin": confirm]) as Message).message
    }
    func removePin(current: String) async throws -> String {
        (try await api.post("/settings/note-pin", ["action": "remove", "currentPin": current]) as Message).message
    }
    func tags() async throws -> [SettingsTag] { (try await api.get("/settings/tags") as Tags).tags }
    func createTag(_ name: String) async throws { try await api.post("/settings/tags", ["name": name]) }
    func renameTag(from old: String, to new: String) async throws { try await api.post("/settings/tags/rename", ["oldName": old, "newName": new], method: "PUT") }
    func deleteTag(_ name: String) async throws { try await api.post("/settings/tags/delete", ["name": name]) }
    func export(_ name: String) async throws -> Data { try await api.data(path: "/api/v1/settings/export/\(name)") }
    func importFiles(_ kind: ImportKind, _ files: [APIClient.UploadFile]) async throws -> String {
        (try await api.upload("/settings/import/\(kind.rawValue)", field: kind == .notes ? "files" : "file", files: files) as Message).message
    }
    func apiTokens() async throws -> [ApiTokenItem] { (try await api.get("/settings/api-tokens") as Tokens).tokens }
    func createApiToken(label: String) async throws -> ApiTokenItem { try await api.post("/settings/api-tokens", ["label": label]) }
    func revokeApiToken(id: Int) async throws { try await api.delete("/settings/api-tokens/\(id)") }
}
