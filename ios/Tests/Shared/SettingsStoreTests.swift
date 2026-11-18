import Foundation
import Testing
@testable import ObeloShared

@MainActor
final class StubSettingsAPI: SettingsAPI {
    struct Failure: LocalizedError { var message = "Stub failure"; var errorDescription: String? { message } }
    var calls: [String] = []
    var failNext: String?
    var data: SettingsData = sampleSettings()
    var sessionList: [DeviceSession] = sampleSessions()
    var notif: NotificationSettings = sampleNotifications()
    var notes = NotesPrefs(autosaveEnabled: true, autosaveDuration: "immediate", hasPin: false, notePaper: "theme")
    var tagList = [SettingsTag(name: "work", count: 3), SettingsTag(name: "home", count: 1)]
    var tokenList: [ApiTokenItem] = []
    var exportBytes = Data("data".utf8)

    private func record(_ s: String) throws {
        calls.append(s)
        if let f = failNext { failNext = nil; throw Failure(message: f) }
    }

    func settings() async throws -> SettingsData { try record("settings"); return data }
    func saveAccount(displayName: String, email: String, timezone: String, timeFormat: String) async throws { try record("saveAccount \(displayName)|\(email)|\(timezone)|\(timeFormat)") }
    func changePassword(current: String, new: String) async throws { try record("password \(current)>\(new)") }
    func sessions() async throws -> [DeviceSession] { try record("sessions"); return sessionList }
    func endSession(key: String) async throws { try record("endSession \(key)"); sessionList.removeAll { $0.key == key } }
    func endOtherSessions() async throws -> Int { try record("endOthers"); return sessionList.filter { !$0.current }.count }
    func uploadAvatar(_ data: Data, filename: String) async throws { try record("avatar \(filename)") }
    func removeAvatar() async throws { try record("removeAvatar") }
    func saveModules(_ list: [(key: String, enabled: Bool)]) async throws { try record("modules " + list.map { "\($0.key):\($0.enabled)" }.joined(separator: ",")) }
    func saveAppearance(theme: String, customAccent: String, customBase: String, statusColors: String) async throws { try record("appearance \(theme) \(customAccent) \(customBase) \(statusColors)") }
    func saveDashboard(_ list: [(key: String, enabled: Bool)]) async throws { try record("dashboard " + list.map { "\($0.key):\($0.enabled)" }.joined(separator: ",")) }
    func deleteAccount(confirmUsername: String) async throws { try record("deleteAccount \(confirmUsername)") }
    func notifications() async throws -> NotificationSettings { try record("notifications"); return notif }
    func saveNotifications(_ s: NotificationSettings) async throws { try record("saveNotifications"); notif = s }
    func testNotification(_ which: String) async throws -> String { try record("test \(which)"); return "Test sent" }
    func newNtfyTopic() async throws -> String { try record("newTopic"); return "obelo-new" }
    func notesPrefs() async throws -> NotesPrefs { try record("notesPrefs"); return notes }
    func saveNotesPrefs(_ p: NotesPrefs) async throws { try record("saveNotes \(p.autosaveEnabled) \(p.autosaveDuration) \(p.notePaper ?? "-")"); notes = p }
    func setPin(current: String, new: String, confirm: String) async throws -> String { try record("setPin"); notes.hasPin = true; return "PIN saved" }
    func removePin(current: String) async throws -> String { try record("removePin \(current)"); notes.hasPin = false; return "PIN removed" }
    func tags() async throws -> [SettingsTag] { try record("tags"); return tagList }
    func createTag(_ name: String) async throws { try record("createTag \(name)"); tagList.append(SettingsTag(name: name, count: 0)) }
    func renameTag(from old: String, to new: String) async throws { try record("renameTag \(old)>\(new)") }
    func deleteTag(_ name: String) async throws { try record("deleteTag \(name)"); tagList.removeAll { $0.name == name } }
    func export(_ name: String) async throws -> Data { try record("export \(name)"); return exportBytes }
    func importFiles(_ kind: ImportKind, _ files: [APIClient.UploadFile]) async throws -> String { try record("import \(kind.rawValue) " + files.map(\.filename).joined(separator: ",")); return "Imported \(files.count)" }
    func apiTokens() async throws -> [ApiTokenItem] { try record("tokens"); return tokenList }
    func createApiToken(label: String) async throws -> ApiTokenItem {
        try record("createToken \(label)")
        let t = ApiTokenItem(id: tokenList.count + 1, label: label.isEmpty ? "iOS Shortcut" : label, createdAt: nil, lastUsed: nil, token: "abc123")
        tokenList.append(ApiTokenItem(id: t.id, label: t.label, createdAt: nil, lastUsed: nil))
        return t
    }
    func revokeApiToken(id: Int) async throws { try record("revoke \(id)"); tokenList.removeAll { $0.id == id } }
}

func sampleSettings() -> SettingsData {
    let json = """
    {"account":{"displayName":"Alice","username":"alice","email":"a@x.test","timezone":"America/Chicago","timeFormat":"12h","avatarUrl":null,"hasCustomAvatar":false,"hasPassword":false,"passwordLogin":true},
     "modules":[{"key":"dashboard","label":"Today","alwaysEnabled":true,"enabled":true},
                {"key":"tasks","label":"Tasks","alwaysEnabled":false,"enabled":true},
                {"key":"notes","label":"Notes","alwaysEnabled":false,"enabled":true},
                {"key":"lists","label":"Lists","alwaysEnabled":false,"enabled":false},
                {"key":"settings","label":"Settings","alwaysEnabled":true,"enabled":true}],
     "appearance":{"theme":"dark","customAccent":"#6366f1","customBase":"dark","statusColors":"catppuccin"},
     "dashboard":[{"key":"focus","enabled":true,"label":"My Focus","description":"x"},{"key":"calendar","enabled":true,"label":"Calendar","description":"y"},{"key":"routines","enabled":false,"label":"Routines","description":"z"}]}
    """
    return try! JSONDecoder().decode(SettingsData.self, from: Data(json.utf8))
}

func sampleSessions() -> [DeviceSession] {
    let json = "[{\"key\":\"a\",\"current\":true,\"device\":\"Mac\",\"ip\":null,\"signedInAt\":null,\"lastSeenAt\":null},{\"key\":\"b\",\"current\":false,\"device\":\"iPhone\",\"ip\":\"1.2.3.4\",\"signedInAt\":null,\"lastSeenAt\":null},{\"key\":\"c\",\"current\":false,\"device\":\"iPad\",\"ip\":null,\"signedInAt\":null,\"lastSeenAt\":null}]"
    return try! JSONDecoder().decode([DeviceSession].self, from: Data(json.utf8))
}

func sampleNotifications() -> NotificationSettings {
    let json = """
    {"pushoverAvailable":true,"pushoverKey":"","pushoverEnabled":false,"ntfyAvailable":true,"ntfyServer":"https://ntfy.test","ntfyEnabled":false,"ntfyTopic":"",
     "emailAvailable":true,"accountEmail":"a@x.test","notifEmail":"",
     "types":{"daily_digest":{"enabled":false,"sendTime":"08:00","channels":{"pushover":false,"email":false,"ntfy":false}},
              "slipping_tasks":{"enabled":false,"sendTime":"09:00","channels":{"pushover":false,"email":false,"ntfy":false}},
              "task_due":{"enabled":true,"sendTime":"","channels":{"pushover":true,"email":false,"ntfy":false}}}}
    """
    return try! JSONDecoder().decode(NotificationSettings.self, from: Data(json.utf8))
}

@MainActor
struct SettingsStoreTests {
    private func make() async -> (SettingsStore, StubSettingsAPI) {
        let api = StubSettingsAPI(); let s = SettingsStore(api: api); await s.load(); return (s, api)
    }

    @Test func loadsEverythingIntoWorkingCopies() async {
        let (s, _) = await make()
        #expect(s.loaded && s.account.displayName == "Alice" && s.account.timezone == "America/Chicago")
        #expect(s.modules.count == 5 && s.look.theme == "dark" && s.widgets.count == 3 && s.sessions.count == 3)
        #expect(!s.isAccountDirty && !s.isModulesDirty && !s.isAppearanceDirty && !s.isDashboardDirty)
    }

    @Test func accountEditsMakeItDirtyAndSaveClearsIt() async {
        let (s, api) = await make()
        s.account.displayName = "Ally"; s.account.timeFormat = "24h"
        #expect(s.isAccountDirty)
        #expect(await s.saveAccount())
        #expect(api.calls.contains("saveAccount Ally|a@x.test|America/Chicago|24h"))
        #expect(!s.isAccountDirty && s.notice == SettingsNotice(text: "Account updated", isError: false))
    }

    @Test func aFailedAccountSaveShowsTheServersWords() async {
        let (s, api) = await make()
        s.account.email = "nope"
        api.failNext = "Enter a valid email address."
        #expect(await s.saveAccount() == false)
        #expect(s.notice == SettingsNotice(text: "Enter a valid email address.", isError: true))
        #expect(s.isAccountDirty, "the edit stays so it can be fixed")
    }

    @Test func passwordNeedsTheTwoNewOnesToMatch() async {
        let (s, api) = await make()
        s.password = .init(current: "", new: "longenough1", again: "different")
        #expect(s.passwordProblem == "The two new passwords don't match" && !s.canSavePassword)
        #expect(await s.savePassword() == false)
        #expect(!api.calls.contains { $0.hasPrefix("password") })
        s.password.again = "longenough1"
        #expect(s.canSavePassword, "no current password is asked for when you have none")
        #expect(await s.savePassword())
        #expect(s.hasPassword && s.password == .init() && api.calls.contains("password >longenough1"))
    }

    @Test func withAPasswordTheCurrentOneIsNeeded() async {
        let api = StubSettingsAPI()
        var d = sampleSettings(); d.account.hasPassword = true; api.data = d
        let s = SettingsStore(api: api); await s.load()
        s.password = .init(current: "", new: "longenough1", again: "longenough1")
        #expect(!s.canSavePassword)
        s.password.current = "old"
        #expect(s.canSavePassword && s.offersPassword)
    }

    @Test func signingOutADeviceAndTheOthers() async {
        let (s, api) = await make()
        #expect(s.otherSessions.count == 2)
        await s.endSession("b")
        #expect(s.sessions.map(\.key) == ["a", "c"] && api.calls.contains("endSession b"))
        await s.endOtherSessions()
        #expect(s.sessions.map(\.key) == ["a"] && s.notice?.text == "Signed out 1 device")
        #expect(SettingsStore.endOthersQuestion(1) == "Sign out 1 other device? You'll stay signed in here.")
        #expect(SettingsStore.endOthersQuestion(3) == "Sign out 3 other devices? You'll stay signed in here.")
    }

    @Test func modulesSwitchOnAndOffButTheFixedOnesStay() async {
        let (s, api) = await make()
        s.toggleModule("dashboard"); s.toggleModule("settings")
        #expect(!s.isModulesDirty, "Today and Settings are always on")
        s.toggleModule("lists"); s.toggleModule("notes")
        #expect(s.isModulesDirty)
        #expect(await s.saveModules())
        #expect(api.calls.contains("modules dashboard:true,tasks:true,notes:false,lists:true,settings:true"), "the saved order is sent back as it was")
        #expect(!s.isModulesDirty)
    }

    @Test func revertingModulesPutsThemBack() async {
        let (s, _) = await make()
        s.toggleModule("tasks")
        #expect(s.isModulesDirty)
        s.revertModules()
        #expect(!s.isModulesDirty)
    }

    @Test func appearanceKnowsWhenItChangedAndValidatesTheAccent() async {
        let (s, api) = await make()
        s.look.theme = "custom"; s.look.customAccent = "#12ab"
        #expect(s.isAppearanceDirty)
        #expect(await s.saveAppearance() == false && s.notice?.text == "Pick an accent colour")
        s.look.customAccent = "#12ABef"
        #expect(await s.saveAppearance())
        #expect(api.calls.contains("appearance custom #12ABef dark catppuccin") && !s.isAppearanceDirty)
        s.look.theme = "dark"; s.revertAppearance()
        #expect(s.look.theme == "custom")
        #expect(SettingsStore.isValidAccent("#00ff00") && !SettingsStore.isValidAccent("00ff00") && !SettingsStore.isValidAccent("#00ff0"))
    }

    @Test func statusColoursOtherThanClassicSaveAsCatppuccin() async {
        let (s, api) = await make()
        s.look.statusColors = "whatever"
        await s.saveAppearance()
        #expect(api.calls.contains { $0.hasSuffix("catppuccin") })
        s.look.statusColors = "tailwind"
        await s.saveAppearance()
        #expect(api.calls.last?.hasSuffix("tailwind") == true)
    }

    @Test func dashboardWidgetsToggleAndReorder() async {
        let (s, api) = await make()
        s.toggleWidget("routines"); s.moveWidget("routines", by: -2)
        #expect(s.widgets.map(\.key) == ["routines", "focus", "calendar"] && s.isDashboardDirty)
        s.moveWidget("calendar", to: "routines")
        #expect(s.widgets.map(\.key) == ["calendar", "routines", "focus"])
        #expect(await s.saveDashboard())
        #expect(api.calls.contains("dashboard calendar:true,routines:true,focus:true"))
    }

    @Test func deletingTheAccountNeedsTheUsernameTyped() async {
        let (s, api) = await make()
        #expect(!s.canDeleteAccount(typed: "") && !s.canDeleteAccount(typed: "alic") && s.canDeleteAccount(typed: "alice"))
        #expect(await s.deleteAccount(typed: "bob") == false)
        #expect(!api.calls.contains { $0.hasPrefix("deleteAccount") })
        #expect(await s.deleteAccount(typed: "alice"))
        api.failNext = "Nope"
        #expect(await s.deleteAccount(typed: "alice") == false && s.notice?.isError == true)
    }

    @Test func avatarUploadAndRemoveReload() async {
        let (s, api) = await make()
        await s.uploadAvatar(Data([1]))
        #expect(api.calls.contains("avatar avatar.jpg") && s.notice?.text == "Avatar updated")
        await s.removeAvatar()
        #expect(api.calls.contains("removeAvatar"))
    }
}

@MainActor
struct NotificationSettingsStoreTests {
    private func make() async -> (NotificationSettingsStore, StubSettingsAPI) {
        let api = StubSettingsAPI(); let s = NotificationSettingsStore(api: api); await s.load(); return (s, api)
    }

    @Test func editingATypeMakesItDirtyAndSaveReloads() async {
        let (s, api) = await make()
        #expect(!s.isDirty)
        s.setType("daily_digest") { $0.enabled = true; $0.sendTime = "07:30"; $0.channels.email = true }
        #expect(s.isDirty && s.settings?.types["daily_digest"]?.sendTime == "07:30")
        #expect(await s.save())
        #expect(!s.isDirty && s.notice?.text == "Notification settings saved" && api.calls.suffix(2) == ["saveNotifications", "notifications"])
    }

    @Test func aTestNeedsTheChangesSavedFirst() async {
        let (s, api) = await make()
        s.setType("task_due") { $0.enabled = false }
        await s.test("ntfy")
        #expect(s.notice == SettingsNotice(text: "Save your changes first", isError: true))
        #expect(!api.calls.contains { $0.hasPrefix("test") })
        await s.save()
        await s.test("email")
        #expect(api.calls.contains("test test-email") && s.notice?.text == "Test sent")
    }

    @Test func aNewTopicReplacesTheOldOne() async {
        let (s, _) = await make()
        await s.newTopic()
        #expect(s.settings?.ntfyTopic == "obelo-new" && !s.isDirty)
        #expect(s.notice?.text == "New topic created — subscribe to it in the ntfy app")
    }

    @Test func channelsAndTimesAreEditable() async {
        let (s, _) = await make()
        s.draft?.pushoverKey = "key123"; s.draft?.pushoverEnabled = true; s.draft?.notifEmail = "me@x.test"
        #expect(s.isDirty && s.settings?.pushoverKey == "key123")
        #expect(NotificationSettingsStore.types.map(\.key) == ["daily_digest", "slipping_tasks", "task_due"])
    }

    @Test func aFailedSaveKeepsTheEditsAndSaysWhy() async {
        let (s, api) = await make()
        s.setType("daily_digest") { $0.enabled = true }
        api.failNext = "Time must be HH:MM"
        #expect(await s.save() == false)
        #expect(s.isDirty && s.notice?.isError == true)
    }
}

@MainActor
struct NoteSettingsStoreTests {
    private func make() async -> (NoteSettingsStore, StubSettingsAPI) {
        let api = StubSettingsAPI(); let s = NoteSettingsStore(api: api); await s.load(); return (s, api)
    }

    @Test func autosaveAndPaperSaveTogether() async {
        let (s, api) = await make()
        s.setAutosave(enabled: false); s.setAutosave(duration: "5min"); s.setPaper("white")
        #expect(s.isDirty)
        #expect(await s.save() && !s.isDirty)
        #expect(api.calls.contains("saveNotes false 5min white"))
    }

    @Test func pinRulesAreCheckedBeforeAsking() async {
        let (s, api) = await make()
        #expect(s.pinProblem(current: "", new: "12", confirm: "12") == "The PIN must be 4 to 6 digits")
        #expect(s.pinProblem(current: "", new: "12ab", confirm: "12ab") == "The PIN must be 4 to 6 digits")
        #expect(s.pinProblem(current: "", new: "1234567", confirm: "1234567") != nil)
        #expect(s.pinProblem(current: "", new: "1234", confirm: "1235") == "The two PINs don't match")
        #expect(s.pinProblem(current: "", new: "123456", confirm: "123456") == nil)
        #expect(await s.setPin(current: "", new: "12", confirm: "12") == false)
        #expect(!api.calls.contains("setPin"))
        #expect(await s.setPin(current: "", new: "1234", confirm: "1234"))
        #expect(s.hasPin && s.notice?.text == "PIN saved")
    }

    @Test func changingAPinNeedsTheCurrentOne() async {
        let (s, api) = await make()
        await s.setPin(current: "", new: "1234", confirm: "1234")
        #expect(s.pinProblem(current: "", new: "5678", confirm: "5678") == "Enter your current PIN")
        #expect(s.pinProblem(current: "1234", new: "5678", confirm: "5678") == nil)
        #expect(await s.removePin(current: "") == false)
        #expect(await s.removePin(current: "1234"))
        #expect(!s.hasPin && api.calls.contains("removePin 1234"))
    }
}

@MainActor
struct TagManagerStoreTests {
    private func make() async -> (TagManagerStore, StubSettingsAPI) {
        let api = StubSettingsAPI(); let s = TagManagerStore(api: api); await s.load(); return (s, api)
    }

    @Test func loadsSortedByName() async {
        let (s, _) = await make()
        #expect(s.tags.map(\.name) == ["home", "work"] && s.loaded)
    }

    @Test func createsLowercaseWithoutAHash() async {
        let (s, api) = await make()
        #expect(await s.create("  #Errands "))
        #expect(api.calls.contains("createTag errands") && s.notice?.text == "#errands created")
        let blank = await s.create("   "), hash = await s.create("#")
        #expect(!blank && !hash)
    }

    @Test func renamingNeedsADifferentName() async {
        let (s, api) = await make()
        let work = s.tags.first { $0.name == "work" }!
        let same = await s.rename(work, to: "work"), blank = await s.rename(work, to: " ")
        #expect(!same && !blank)
        #expect(await s.rename(work, to: "Job"))
        #expect(api.calls.contains("renameTag work>job") && s.notice?.text == "#work renamed to #job")
    }

    @Test func deletingAsksWithTheCount() async {
        let (s, _) = await make()
        let work = s.tags.first { $0.name == "work" }!
        #expect(TagManagerStore.deleteQuestion(work) == "Delete tag \"work\" from all 3 items?")
        #expect(TagManagerStore.deleteQuestion(SettingsTag(name: "x", count: 1)) == "Delete tag \"x\" from all 1 item?")
        #expect(await s.delete(work))
        #expect(s.tags.map(\.name) == ["home"] && s.notice?.text == "#work deleted from all items")
    }

    @Test func aFailureSaysWhy() async {
        let (s, api) = await make()
        api.failNext = "Tag already exists"
        #expect(await s.create("home") == false && s.notice == SettingsNotice(text: "Tag already exists", isError: true))
    }
}

@MainActor
struct DataTransferStoreTests {
    @Test func exportNamesTheFileForToday() async {
        let api = StubSettingsAPI(); let s = DataTransferStore(api: api)
        let f = await s.export(ExportKind.all[1], on: "2026-11-15")
        #expect(f == ExportedFile(filename: "obelo-tasks-2026-11-15.csv", data: Data("data".utf8)))
        #expect(ExportKind.all[0].filename(on: "2026-11-15") == "obelo-export-2026-11-15.json")
        #expect(ExportKind.all[4].filename(on: "2026-11-15") == "obelo-bookmarks-2026-11-15.html")
        #expect(s.busy == nil)
        api.failNext = "Couldn't load the file."
        #expect(await s.export(ExportKind.all[0], on: "x") == nil && s.notice?.isError == true)
    }

    @Test func importAddsTheExtensionTheServerGoesBy() async {
        let api = StubSettingsAPI(); let s = DataTransferStore(api: api)
        #expect(await s.importFiles(.notes, [("one", Data([1])), ("two.md", Data([2]))]))
        #expect(api.calls.last == "import notes one.md,two.md" && s.notice == SettingsNotice(text: "Imported 2", isError: false))
        #expect(await s.importFiles(.tasks, [("t.CSV", Data([1]))]))
        #expect(api.calls.last == "import tasks t.CSV")
        #expect(ImportKind.notes.allowsSeveralFiles && !ImportKind.json.allowsSeveralFiles)
    }

    @Test func importWithNoReadableFileSaysSo() async {
        let s = DataTransferStore(api: StubSettingsAPI())
        #expect(await s.importFiles(.json, []) == false && s.notice?.text == "Couldn't read that file.")
    }

    @Test func aFailedImportShowsTheServersWords() async {
        let api = StubSettingsAPI(); let s = DataTransferStore(api: api)
        api.failNext = "That isn't a valid export."
        #expect(await s.importFiles(.json, [("a.json", Data([1]))]) == false && s.notice?.text == "That isn't a valid export.")
    }
}

@MainActor
struct ApiTokensStoreTests {
    @Test func creatingShowsTheTokenOnceAndTheListKeepsNoToken() async {
        let api = StubSettingsAPI(); let s = ApiTokensStore(api: api)
        s.label = "  iPhone Shortcut "
        #expect(await s.create())
        #expect(api.calls.contains("createToken iPhone Shortcut"))
        #expect(s.fresh?.token == "abc123" && s.label.isEmpty)
        #expect(s.tokens.count == 1 && s.tokens[0].token == nil)
        s.dismissFresh()
        #expect(s.fresh == nil)
    }

    @Test func anEmptyLabelIsLeftForTheServerToName() async {
        let api = StubSettingsAPI(); let s = ApiTokensStore(api: api)
        await s.create()
        #expect(api.calls.contains("createToken ") && s.tokens.first?.label == "iOS Shortcut")
    }

    @Test func revokingRemovesItAndHidesAFreshOne() async {
        let api = StubSettingsAPI(); let s = ApiTokensStore(api: api)
        await s.create()
        let t = s.tokens[0]
        await s.revoke(t)
        #expect(s.tokens.isEmpty && s.fresh == nil && api.calls.contains("revoke 1"))
        #expect(ApiTokensStore.revokeQuestion == "Revoke this token? Any Shortcut using it will stop working.")
    }

    @Test func aFailureSaysWhy() async {
        let api = StubSettingsAPI(); let s = ApiTokensStore(api: api)
        api.failNext = "Down"
        #expect(await s.create() == false && s.notice?.isError == true && s.fresh == nil)
    }

    @Test func theHowToNamesThisServer() {
        let lines = ApiTokensStore.howTo(server: "https://obelo.example.com")
        #expect(lines[0].contains("https://obelo.example.com/capture/api") && lines[0].contains("Bearer <your-token>"))
    }
}
