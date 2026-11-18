import Foundation
import Testing
@testable import ObeloShared

@MainActor
final class StubSourcesAPI: CalendarSourcesAPI {
    struct Failure: LocalizedError { let text: String; var errorDescription: String? { text } }
    var accounts: [CalendarAccount] = []
    var own: [OwnCalendar] = []
    var people = [ShareableUser(id: 2, username: "bob", displayName: "Bob B"), ShareableUser(id: 3, username: "carol", displayName: nil)]
    var defaultTarget = "local"
    var calls: [String] = []
    var failWith: String?
    var connectResult = ConnectResult(found: 2, synced: 5, syncError: nil)
    var selectResult = SelectResult(selected: 1, count: 3, syncError: nil)

    private func record(_ s: String) throws {
        calls.append(s)
        if let text = failWith { failWith = nil; throw Failure(text: text) }
    }

    func overview() async throws -> CalendarSourcesOverview {
        calls.append("overview")
        return CalendarSourcesOverview(sources: accounts, localCalendars: own, shareableUsers: people, defaultTarget: defaultTarget,
                                       targets: [CalendarChoice(value: "local", label: "Local only", color: "#374151")], googleConfigured: false)
    }
    func connect(_ d: CaldavDraft) async throws -> ConnectResult {
        try record("connect \(d.username) \(d.body["serverUrl"] as? String ?? "")")
        accounts.append(account(10, d.name.isEmpty ? "iCloud Calendar" : d.name)); return connectResult
    }
    func sync(id: Int) async throws -> SyncResult { try record("sync \(id)"); return SyncResult(count: 4, name: accounts.first { $0.id == id }?.name ?? "?") }
    func setColor(id: Int, _ color: String) async throws {
        try record("color \(id) \(color)"); if let i = accounts.firstIndex(where: { $0.id == id }) { accounts[i].color = color }
    }
    func remove(id: Int) async throws { try record("remove \(id)"); accounts.removeAll { $0.id == id } }
    func setCalendars(id: Int, urls: [String]) async throws -> SelectResult { try record("calendars \(id) \(urls.joined(separator: ","))"); return selectResult }
    func setFamily(id: Int, url: String?) async throws { try record("family \(id) \(url ?? "none")") }
    func setDefault(_ target: String) async throws { try record("default \(target)"); defaultTarget = target }
    func createLocal(name: String, color: String) async throws {
        try record("createLocal \(name)"); own.append(OwnCalendar(id: 50, name: name, color: color, members: []))
    }
    func updateLocal(id: Int, name: String, color: String) async throws {
        try record("updateLocal \(id) \(name)"); if let i = own.firstIndex(where: { $0.id == id }) { own[i].name = name; own[i].color = color }
    }
    func deleteLocal(id: Int) async throws { try record("deleteLocal \(id)"); own.removeAll { $0.id == id } }
    func addMember(calendar: Int, username: String) async throws {
        try record("addMember \(calendar) \(username)")
        if let i = own.firstIndex(where: { $0.id == calendar }), let p = people.first(where: { $0.username == username }) {
            own[i].members.append(CalendarMember(userId: p.id, username: p.username, displayName: p.displayName, canEdit: true))
        }
    }
    func removeMember(calendar: Int, userId: Int) async throws {
        try record("removeMember \(calendar) \(userId)")
        if let i = own.firstIndex(where: { $0.id == calendar }) { own[i].members.removeAll { $0.userId == userId } }
    }
}

private func account(_ id: Int, _ name: String, type: String = "caldav") -> CalendarAccount {
    CalendarAccount(id: id, type: type, name: name, color: "#112233", active: true, lastSynced: nil, isFamily: false, calendars: [
        SourceCalendar(url: "https://x/work/", name: "Work", color: nil, selected: true, isFamily: false),
        SourceCalendar(url: "https://x/home/", name: "Home", color: nil, selected: true, isFamily: false)])
}

@MainActor
struct CalendarSourcesStoreTests {
    private func make() -> (CalendarSourcesStore, StubSourcesAPI) {
        let api = StubSourcesAPI(); api.accounts = [account(1, "Work")]
        return (CalendarSourcesStore(api: api), api)
    }

    @Test func loadsAccountsAndYourCalendars() async {
        let (store, api) = make(); api.own = [OwnCalendar(id: 5, name: "Family", color: "#abcdef", members: [])]
        await store.load()
        #expect(store.accounts.map(\.name) == ["Work"])
        #expect(store.ownCalendars.map(\.name) == ["Family"])
        #expect(store.defaultTarget == "local")
        #expect(store.failure == nil)
    }

    @Test func aFailedConnectSaysWhy() async {
        let (store, api) = make()
        await store.load()
        api.failWith = "Could not connect: 401"
        let ok = await store.connect(CaldavDraft())
        #expect(!ok)
        #expect(store.failure == "Could not connect: 401")
        #expect(store.notice == nil)
    }

    @Test func connectingAnAppleAccountUsesICloudAndReportsWhatWasFound() async {
        let (store, api) = make(); await store.load()
        var d = CaldavDraft(); d.username = "me@icloud.com"; d.password = "abcd-efgh"
        #expect(d.canSubmit)
        #expect(await store.connect(d))
        #expect(api.calls.contains("connect me@icloud.com https://caldav.icloud.com"))
        #expect(store.notice == "Connected! Found 2 calendars. Synced 5 events.")
        #expect(store.accounts.count == 2)
    }

    @Test func aFirstSyncFailureIsShownButTheAccountStays() async {
        let (store, api) = make(); api.connectResult = ConnectResult(found: 1, synced: nil, syncError: "Initial sync failed: timeout")
        var d = CaldavDraft(); d.username = "u"; d.password = "p"
        _ = await store.connect(d)
        #expect(store.notice == "Connected! Found 1 calendar. Initial sync failed: timeout")
        #expect(store.accounts.count == 2)
    }

    @Test func otherProvidersNeedAServerAddress() {
        var d = CaldavDraft(); d.provider = .other; d.username = "u"; d.password = "p"
        #expect(!d.canSubmit)
        d.serverUrl = " https://dav.example "
        #expect(d.canSubmit)
        #expect(d.body["serverUrl"] as? String == "https://dav.example")
        d.provider = .apple; d.serverUrl = ""
        #expect(d.canSubmit)
        d.password = ""
        #expect(!d.canSubmit)
    }

    @Test func syncNowSaysHowManyEventsAndMarksTheAccountBusyOnlyWhileItRuns() async {
        let (store, _) = make(); await store.load()
        await store.sync(store.accounts[0])
        #expect(store.notice == "Synced 4 events from Work.")
        #expect(store.syncing.isEmpty)
    }

    @Test func choosingCalendarsAndTheFamilyOneGoToTheServer() async {
        let (store, api) = make(); await store.load()
        await store.setCalendars(store.accounts[0], urls: ["https://x/work/"])
        #expect(api.calls.contains("calendars 1 https://x/work/"))
        #expect(store.notice == "Saved. Synced 3 events from 1 calendar.")
        await store.setFamily(store.accounts[0], url: "https://x/home/")
        await store.setFamily(store.accounts[0], url: nil)
        #expect(api.calls.contains("family 1 https://x/home/") && api.calls.contains("family 1 none"))
    }

    @Test func removingAnAccountDropsItFromTheList() async {
        let (store, _) = make(); await store.load()
        await store.remove(store.accounts[0])
        #expect(store.accounts.isEmpty)
        #expect(store.notice == "Removed Work.")
    }

    @Test func yourOwnCalendarsNeedANameAndShareByUsername() async {
        let (store, api) = make(); await store.load()
        #expect(!(await store.createOwn(name: "   ", color: "#111111")))
        #expect(store.failure == "Name is required.")
        #expect(await store.createOwn(name: " Family ", color: "#111111"))
        #expect(store.ownCalendars.map(\.name) == ["Family"])
        let cal = store.ownCalendars[0]
        #expect(store.peopleToAdd(to: cal).map(\.username) == ["bob", "carol"])
        #expect(await store.addMember(cal, username: "bob"))
        #expect(store.notice == "bob added to \"Family\".")
        #expect(store.peopleToAdd(to: store.ownCalendars[0]).map(\.username) == ["carol"])
        #expect(store.ownCalendars[0].members[0].shownName == "Bob B")
        await store.removeMember(store.ownCalendars[0], store.ownCalendars[0].members[0])
        #expect(store.ownCalendars[0].members.isEmpty)
        await store.deleteOwn(store.ownCalendars[0])
        #expect(store.ownCalendars.isEmpty)
        #expect(api.calls.contains("deleteLocal 50"))
    }

    @Test func aFailureShowsItsMessageAndLeavesTheListAlone() async {
        let (store, api) = make(); await store.load()
        api.failWith = "Something went wrong."
        await store.remove(store.accounts[0])
        #expect(store.failure == "Something went wrong.")
        #expect(store.accounts.count == 1)
    }

    @Test func aMemberWithNoDisplayNameShowsTheUsername() {
        #expect(CalendarMember(userId: 3, username: "carol", displayName: "", canEdit: true).shownName == "carol")
    }

    @Test func settingTheDefaultCalendarRemembersIt() async {
        let (store, api) = make(); await store.load()
        await store.setDefault("local_calendar|5")
        #expect(api.calls.contains("default local_calendar|5"))
        #expect(store.defaultTarget == "local_calendar|5")
    }

    @Test func decodesWhatTheServerSends() throws {
        let json = """
        {"sources":[{"id":1,"type":"google","name":"Google (a@b.c)","color":"#4285f4","active":true,"lastSynced":null,"isFamily":false,
          "calendars":[{"url":"https://u/","name":"Primary","color":"#4285f4","selected":true,"isFamily":false}]}],
         "localCalendars":[{"id":2,"name":"Home","color":"#6366f1","members":[{"userId":3,"username":"bob","displayName":"Bob","canEdit":true}]}],
         "shareableUsers":[{"id":3,"username":"bob","displayName":"Bob"}],"defaultTarget":"local",
         "targets":[{"value":"local","label":"Local only","color":"#374151"}],"googleConfigured":true}
        """
        let d = try JSONDecoder().decode(CalendarSourcesOverview.self, from: Data(json.utf8))
        #expect(d.sources[0].isGoogle && d.sources[0].kindLabel == "Google Calendar")
        #expect(d.localCalendars[0].members[0].username == "bob")
        #expect(d.googleConfigured == true)
    }
}
