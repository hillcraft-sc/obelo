import Foundation
import Testing
@testable import ObeloShared

func makeReminder(_ id: Int, title: String = "Reminder", due: String = "2026-11-20", time: String = "09:00",
                  completed: Bool = false, state: String? = nil, tags: [String] = [], offset: Int? = nil,
                  recurring: Bool = false) -> ReminderItem {
    var obj: [String: Any] = [
        "id": id, "title": title, "notes": "", "dueDate": due, "dueTime": time, "priority": "none", "tags": tags,
        "completed": completed, "recurring": recurring, "recurLabel": "", "createdAt": "2026-11-14T10:00:00.000Z",
    ]
    if let state { obj["dueState"] = state }
    if let offset { obj["reminderOffset"] = offset }
    let d = JSONDecoder()
    d.dateDecodingStrategy = .custom { dec in
        try Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(try dec.singleValueContainer().decode(String.self))
    }
    return try! d.decode(ReminderItem.self, from: JSONSerialization.data(withJSONObject: obj))
}

/// A fake server: reminders in memory, a log of calls, and a switch to make the next call fail
@MainActor
final class StubRemindersAPI: RemindersAPI {
    struct Failure: LocalizedError { var errorDescription: String? { "Stub failure" } }
    var reminders: [ReminderItem]
    var calls: [String] = []
    var failNext = false
    var lastBody: [String: Any] = [:]
    var nextId = 100

    init(_ reminders: [ReminderItem] = []) { self.reminders = reminders }

    private func record(_ s: String) throws { calls.append(s); if failNext { failNext = false; throw Failure() } }

    func list(view: String, tag: String?) async throws -> RemindersListResponse {
        try record("list \(view) \(tag ?? "-")")
        return RemindersListResponse(reminders: reminders, tags: ["work"], counts: .init(overdue: 1, today: reminders.count))
    }
    func detail(id: Int) async throws -> ReminderItem {
        try record("detail \(id)")
        return reminders.first { $0.id == id } ?? makeReminder(id)
    }
    func create(_ body: [String: Any]) async throws -> ReminderItem {
        try record("create"); lastBody = body
        nextId += 1
        let r = makeReminder(nextId, title: body["title"] as? String ?? "")
        reminders.append(r)
        return r
    }
    func update(id: Int, _ body: [String: Any]) async throws -> ReminderItem {
        try record("update \(id)"); lastBody = body
        let r = makeReminder(id, title: body["title"] as? String ?? "", due: body["dueDate"] as? String ?? "", time: body["dueTime"] as? String ?? "")
        if let i = reminders.firstIndex(where: { $0.id == id }) { reminders[i] = r }
        return r
    }
    func complete(id: Int) async throws { try record("complete \(id)"); reminders.removeAll { $0.id == id } }
    func restore(id: Int) async throws { try record("restore \(id)"); reminders.removeAll { $0.id == id } }
    func delete(id: Int) async throws { try record("delete \(id)"); reminders.removeAll { $0.id == id } }
    func snooze(id: Int, duration: String) async throws { try record("snooze \(id) \(duration)") }
    func bulk(action: String, ids: [Int]) async throws -> Int {
        try record("bulk \(action) \(ids.sorted())")
        let n = reminders.filter { ids.contains($0.id) }.count
        reminders.removeAll { ids.contains($0.id) }
        return n
    }
    func allTags() async throws -> [String] { try record("tags"); return ["work", "home"] }
}

@MainActor
struct RemindersStoreTests {
    func make(_ items: [ReminderItem]? = nil) async -> (RemindersStore, StubRemindersAPI) {
        let api = StubRemindersAPI(items ?? [makeReminder(1, title: "One"), makeReminder(2, title: "Two"), makeReminder(3, title: "Three")])
        let store = RemindersStore(api: api)
        await store.load()
        return (store, api)
    }

    @Test func loadsTheListTheTagsAndTheCounts() async {
        let (s, _) = await make()
        #expect(s.reminders.map(\.id) == [1, 2, 3])
        #expect(s.tagList == ["work"])
        #expect(s.counts == .init(overdue: 1, today: 3))
        #expect(s.loaded)
    }

    @Test func switchingTabAndTagAsksTheServerForThem() async {
        let (s, api) = await make()
        await s.show(view: "overdue")
        await s.toggleTag("work")
        #expect(api.calls.last == "list overdue work")
        await s.toggleTag("work")
        #expect(s.tag == nil)
        #expect(api.calls.last == "list overdue -")
        #expect(s.view == "overdue")
    }

    @Test func oneSelectedRowOpensItAndSeveralDoNot() async {
        let (s, api) = await make()
        await s.select([2])
        #expect(s.open?.id == 2)
        #expect(api.calls.contains("detail 2"))
        await s.select([1, 2])
        #expect(s.open == nil)
        #expect(s.selection == [1, 2])
    }

    @Test func aTabForAReminderComesFromItsState() {
        #expect(RemindersStore.view(for: makeReminder(1, completed: true)) == "completed")
        #expect(RemindersStore.view(for: makeReminder(1, state: "overdue")) == "overdue")
        #expect(RemindersStore.view(for: makeReminder(1, state: "today")) == "upcoming")
        #expect(RemindersStore.view(for: makeReminder(1)) == "upcoming")
    }

    @Test func completeRestoreSnoozeAndDeleteAskTheServerAndReloadTheList() async {
        let (s, api) = await make()
        await s.select([1])
        await s.complete(1)
        #expect(api.calls.contains("complete 1"))
        #expect(s.reminders.map(\.id) == [2, 3])
        #expect(s.open == nil && s.selection.isEmpty)
        await s.snooze(2, "1hour")
        #expect(api.calls.contains("snooze 2 1hour"))
        await s.delete(3)
        #expect(api.calls.contains("delete 3"))
        await s.restore(2)
        #expect(api.calls.contains("restore 2"))
        #expect(api.calls.filter { $0.hasPrefix("list") }.count == 5)   // the first load, then one after each of the four
    }

    @Test func aFailedCallShowsTheErrorAndKeepsTheRow() async {
        let (s, api) = await make()
        api.failNext = true
        await s.complete(1)
        #expect(s.error == "Stub failure")
        #expect(s.reminders.map(\.id) == [1, 2, 3])
    }

    @Test func bulkCompleteAndDeleteUseOneRequestEach() async {
        let (s, api) = await make()
        s.selection = [1, 2]
        let n = await s.applyBulk("complete")
        #expect(n == 2)
        #expect(api.calls.filter { $0.hasPrefix("bulk") } == ["bulk complete [1, 2]"])
        #expect(s.selection.isEmpty)
        #expect(s.reminders.map(\.id) == [3])
        s.selection = [3]
        _ = await s.applyBulk("delete")
        #expect(api.calls.last(where: { $0.hasPrefix("bulk") }) == "bulk delete [3]")
    }

    @Test func aFailedBulkKeepsTheSelectionAndSaysSo() async {
        let (s, api) = await make()
        s.selection = [1, 2]
        api.failNext = true
        let n = await s.applyBulk("delete")
        #expect(n == 0)
        #expect(s.error == "Stub failure")
        #expect(s.selection == [1, 2])
    }

    @Test func bulkChoicesAreMarkCompleteAndDeleteExceptOnCompleted() async {
        let (s, _) = await make()
        #expect(s.bulkChoices.map(\.0) == ["complete", "delete"])
        await s.show(view: "completed")
        #expect(s.bulkChoices.map(\.0) == ["delete"])
    }

    @Test func aReminderNeedsATitleADateAndATime() {
        var d = ReminderDraft()
        #expect(!d.isComplete)
        d.title = "Call Dana"
        #expect(!d.isComplete)
        d.dueDate = "2026-11-20"; d.dueTime = "09:00"
        #expect(d.isComplete)
        d.title = "   "
        #expect(!d.isComplete)
    }

    @Test func aBlankReminderStartsToday_atTheNextFullHour() {
        let tz = TimeZone(identifier: "America/New_York")!
        var cal = Calendar(identifier: .gregorian); cal.timeZone = tz
        let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 15, hour: 10, minute: 20))!
        let d = ReminderDraft.blank(now: now, in: tz)
        #expect(d.dueDate == "2026-11-15")
        #expect(d.dueTime == "11:00")
        #expect(d.reminderOffset == 0)
        let late = cal.date(from: DateComponents(year: 2026, month: 11, day: 15, hour: 23, minute: 40))!
        let d2 = ReminderDraft.blank(now: late, in: tz)
        #expect(d2.dueDate == "2026-11-16")
        #expect(d2.dueTime == "00:00")
    }

    @Test func createNeedsAFullDraftAndSendsEveryField() async {
        let (s, api) = await make()
        let none = await s.create(ReminderDraft())
        #expect(none == nil)
        #expect(s.error == "Title, date, and time are required.")
        #expect(!api.calls.contains("create"))
        var d = ReminderDraft.blank()
        d.title = "Call Dana"; d.reminderOffset = 15; d.tags = ["work"]
        let made = await s.create(d)
        #expect(made?.title == "Call Dana")
        #expect(api.lastBody["reminderOffset"] as? Int == 15)
        #expect(api.lastBody["tags"] as? [String] == ["work"])
        #expect(api.lastBody["recurring"] as? Bool == false)
    }

    @Test func saveUpdatesTheRowAndTheOpenReminder() async {
        let (s, api) = await make()
        await s.select([1])
        var d = ReminderDraft(s.open!)
        d.title = "Renamed"
        let ok = await s.save(1, d)
        #expect(ok)
        #expect(api.calls.contains("update 1"))
        #expect(s.reminders.first { $0.id == 1 }?.title == "Renamed")
        #expect(s.open?.title == "Renamed")
    }

    @Test func aDraftWithNoTitleIsNotSaved() async {
        let (s, api) = await make()
        var d = ReminderDraft(makeReminder(1))
        d.title = ""
        let ok = await s.save(1, d)
        #expect(!ok)
        #expect(!api.calls.contains("update 1"))
    }
}
