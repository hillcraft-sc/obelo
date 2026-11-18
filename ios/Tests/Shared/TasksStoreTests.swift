import Foundation
import Testing
@testable import ObeloShared

func makeTask(_ id: Int, title: String = "Task", status: String = "inbox", priority: String = "none",
              subtasks: [(Int, String, Bool)]? = nil) -> TaskItem {
    var obj: [String: Any] = [
        "id": id, "title": title, "notes": "", "status": status, "priority": priority, "tags": [String](),
        "recurring": false, "createdAt": "2026-11-14T10:00:00.000Z", "updatedAt": "2026-11-14T10:00:00.000Z",
    ]
    if let subtasks { obj["subtasks"] = subtasks.map { ["id": $0.0, "title": $0.1, "done": $0.2] as [String: Any] } }
    let data = try! JSONSerialization.data(withJSONObject: obj)
    let d = JSONDecoder()
    d.dateDecodingStrategy = .custom { dec in
        let s = try dec.singleValueContainer().decode(String.self)
        return try Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(s)
    }
    return try! d.decode(TaskItem.self, from: data)
}

/// A fake server: a list of tasks in memory, a log of calls, and a switch to make the next call fail
@MainActor
final class StubTasksAPI: TasksAPI {
    struct Failure: LocalizedError { var errorDescription: String? { "Stub failure" } }
    var tasks: [TaskItem]
    var calls: [String] = []
    var failNext = false
    var lastBody: [String: Any] = [:]
    var nextId = 100

    init(_ tasks: [TaskItem] = []) { self.tasks = tasks }

    private func record(_ s: String) throws { calls.append(s); if failNext { failNext = false; throw Failure() } }

    func list(view: String, tag: String?, search: String?) async throws -> TasksListResponse {
        try record("list \(view) \(tag ?? "-") \(search ?? "-")")
        return TasksListResponse(tasks: tasks, tags: ["work"], counts: .init(today: 2, inbox: tasks.count, slipping: 1))
    }
    func detail(id: Int) async throws -> TaskItem {
        try record("detail \(id)")
        return tasks.first { $0.id == id } ?? makeTask(id)
    }
    func create(_ body: [String: Any]) async throws -> TaskItem {
        try record("create"); lastBody = body
        nextId += 1
        let t = makeTask(nextId, title: body["title"] as? String ?? "", status: body["status"] as? String ?? "inbox")
        tasks.insert(t, at: 0)
        return t
    }
    func update(id: Int, _ body: [String: Any]) async throws -> TaskItem {
        try record("update \(id)"); lastBody = body
        let t = makeTask(id, title: body["title"] as? String ?? "", status: body["status"] as? String ?? "inbox",
                         priority: body["priority"] as? String ?? "none")
        if let i = tasks.firstIndex(where: { $0.id == id }) { tasks[i] = t }
        return t
    }
    func complete(id: Int) async throws { try record("complete \(id)"); tasks.removeAll { $0.id == id } }
    func restore(id: Int) async throws { try record("restore \(id)"); tasks.removeAll { $0.id == id } }
    func delete(id: Int) async throws { try record("delete \(id)"); tasks.removeAll { $0.id == id } }
    func bulk(action: String, ids: [Int]) async throws { try record("bulk \(action) \(ids.sorted())"); tasks.removeAll { ids.contains($0.id) } }
    func addSubtask(taskId: Int, title: String) async throws { try record("addSub \(taskId) \(title)") }
    func toggleSubtask(taskId: Int, subtaskId: Int) async throws { try record("toggleSub \(taskId) \(subtaskId)") }
    func deleteSubtask(taskId: Int, subtaskId: Int) async throws { try record("deleteSub \(taskId) \(subtaskId)") }
    func allTags() async throws -> [String] { ["work", "home"] }
}

@MainActor
struct TasksStoreTests {
    func store(_ tasks: [TaskItem] = [makeTask(1), makeTask(2), makeTask(3)]) -> (TasksStore, StubTasksAPI) {
        let api = StubTasksAPI(tasks)
        return (TasksStore(api: api), api)
    }

    @Test func loadFillsListTagsAndCounts() async {
        let (s, _) = store()
        await s.load()
        #expect(s.tasks.map(\.id) == [1, 2, 3])
        #expect(s.tagList == ["work"])
        #expect(s.counts.today == 2 && s.counts.slipping == 1)
        #expect(s.loaded && s.error == nil)
    }

    @Test func loadFailureKeepsTheListAndSetsAnError() async {
        let (s, api) = store()
        await s.load()
        api.failNext = true
        await s.load()
        #expect(s.tasks.count == 3)
        #expect(s.error == "Stub failure")
    }

    @Test func switchingViewPassesViewTagAndSearch() async {
        let (s, api) = store()
        s.search = "milk"
        await s.toggleTag("work")
        #expect(api.calls.last == "list inbox work milk")
        await s.show(view: "today")
        #expect(api.calls.last == "list today work milk")
        await s.toggleTag("work")
        #expect(s.tag == nil)
    }

    @Test func clearFilterResetsTagAndSearch() async {
        let (s, _) = store()
        s.search = "x"; s.tag = "work"
        await s.clearFilter()
        #expect(s.tag == nil && s.search.isEmpty && !s.isFiltered)
    }

    @Test func quickAddTrimsInsertsAtTopAndUsesTodayOnTheTodayTab() async {
        let (s, api) = store()
        await s.load()
        #expect(await s.quickAdd("   ") == nil)
        let t = await s.quickAdd("  Buy milk  ")
        #expect(t?.title == "Buy milk")
        #expect(s.tasks.first?.title == "Buy milk")
        #expect(api.lastBody["status"] as? String == "inbox")
        await s.show(view: "today")
        _ = await s.quickAdd("Call")
        #expect(api.lastBody["status"] as? String == "today")
    }

    @Test func quickAddIsOffOnCompletedSlippingArchived() {
        let (s, _) = store()
        for v in ["completed", "slipping", "archived"] { s.view = v; #expect(!s.canQuickAdd) }
        s.view = "upcoming"; #expect(s.canQuickAdd)
    }

    @Test func completeRestoreDeleteRemoveTheRowAndClearTheOpenTask() async {
        let (s, api) = store()
        await s.load()
        await s.select([2])
        #expect(s.open?.id == 2)
        await s.complete(2)
        #expect(!s.tasks.contains { $0.id == 2 } && s.open == nil && s.selection.isEmpty)
        await s.restore(1)
        await s.delete(3)
        #expect(s.tasks.isEmpty)
        #expect(api.calls.contains("complete 2") && api.calls.contains("restore 1") && api.calls.contains("delete 3"))
    }

    @Test func failedCompleteKeepsTheRowAndShowsTheError() async {
        let (s, api) = store()
        await s.load()
        api.failNext = true
        await s.complete(1)
        #expect(s.tasks.count == 3)
        #expect(s.error == "Stub failure")
    }

    @Test func oneSelectedRowOpensTheTaskManyDoNot() async {
        let (s, _) = store()
        await s.load()
        await s.select([1])
        #expect(s.open?.id == 1 && !s.bulkMode)
        await s.select([1, 2])
        #expect(s.open == nil && s.bulkMode)
        await s.select([])
        #expect(s.open == nil && s.selection.isEmpty)
    }

    @Test func saveSendsEveryFieldAndUpdatesTheRow() async {
        let (s, api) = store()
        await s.load()
        await s.select([1])
        var d = TaskDraft(s.open!)
        d.title = "Renamed"; d.priority = "high"; d.dueDate = "2026-12-01"; d.recurring = true; d.recurRule = "weekly"
        #expect(await s.save(1, d))
        #expect(s.tasks.first { $0.id == 1 }?.title == "Renamed")
        #expect(s.open?.title == "Renamed")
        let b = api.lastBody
        #expect(b["title"] as? String == "Renamed" && b["priority"] as? String == "high")
        #expect(b["dueDate"] as? String == "2026-12-01" && b["recurRule"] as? String == "weekly")
        #expect(b["dueTime"] is NSNull)
        #expect(Set(b.keys) == ["title", "notes", "status", "priority", "dueDate", "dueTime", "tags", "recurring", "recurRule"])
    }

    @Test func failedSaveReturnsFalseAndLeavesTheTask() async {
        let (s, api) = store()
        await s.load()
        await s.select([1])
        api.failNext = true
        var d = TaskDraft(s.open!); d.title = "X"
        #expect(await s.save(1, d) == false)
        #expect(s.open?.title == "Task" && s.error != nil)
    }

    @Test func setStatusAndPrioritySaveJustThatChange() async {
        let (s, api) = store()
        await s.load()
        await s.setStatus(1, "in-progress")
        #expect(api.lastBody["status"] as? String == "in-progress" && api.lastBody["title"] as? String == "Task")
        await s.setPriority(1, "high")
        #expect(api.lastBody["priority"] as? String == "high")
    }

    @Test func bulkSendsTheSelectionThenReloadsAndClears() async {
        let (s, api) = store()
        await s.load()
        await s.select([1, 3])
        await s.applyBulk("archive")
        #expect(api.calls.contains("bulk archive [1, 3]"))
        #expect(s.selection.isEmpty && s.tasks.map(\.id) == [2])
    }

    @Test func bulkFailureKeepsTheSelection() async {
        let (s, api) = store()
        await s.load()
        await s.select([1, 2])
        api.failNext = true
        await s.applyBulk("complete")
        #expect(s.selection == [1, 2] && s.error != nil)
    }

    @Test func bulkChoicesFollowTheTab() {
        let (s, _) = store()
        #expect(s.bulkChoices.map(\.0).contains("archive") && !s.bulkChoices.map(\.0).contains("restore"))
        s.view = "archived"
        #expect(s.bulkChoices.map(\.0).contains("restore") && !s.bulkChoices.map(\.0).contains("archive"))
        #expect(s.bulkChoices.count == 6)
    }

    @Test func deleteSelectedRemovesAllOfThem() async {
        let (s, api) = store()
        await s.load()
        await s.select([1, 2])
        await s.deleteSelected()
        #expect(s.tasks.map(\.id) == [3] && s.selection.isEmpty)
        #expect(api.calls.filter { $0.hasPrefix("delete") }.count == 2)
    }

    @Test func subtaskCallsReloadTheOpenTask() async {
        let (s, api) = store([makeTask(1, subtasks: [(5, "a", false)])])
        await s.load()
        await s.select([1])
        await s.addSubtask("  new  ")
        await s.addSubtask("   ")
        await s.toggleSubtask(5)
        await s.deleteSubtask(5)
        #expect(api.calls.filter { $0.hasPrefix("addSub") } == ["addSub 1 new"])
        #expect(api.calls.contains("toggleSub 1 5") && api.calls.contains("deleteSub 1 5"))
        #expect(api.calls.filter { $0 == "detail 1" }.count == 4)
    }

    @Test func createFromADraftReloads() async {
        let (s, api) = store([])
        var d = TaskDraft(); d.title = "Plan"; d.status = "today"
        let t = await s.create(d)
        #expect(t?.title == "Plan" && s.tasks.first?.title == "Plan")
        #expect(api.lastBody["status"] as? String == "today")
    }
}

struct RecurrenceRuleTests {
    @Test func fixedChoicesRoundTrip() {
        for (raw, _) in RecurrenceRule.presets {
            let r = RecurrenceRule(raw)
            #expect(r.raw == raw && !r.isCustom)
        }
    }
    @Test func emptyOrNilIsDaily() {
        #expect(RecurrenceRule(nil).raw == "daily")
        #expect(RecurrenceRule("").raw == "daily")
    }
    @Test func customRoundTrips() {
        for raw in ["custom:daily:3", "custom:weekly:2", "custom:yearly:1", "custom:monthly:2:each:15",
                    "custom:monthly:1:onthe:last:friday", "custom:monthly:3:onthe:first:sunday"] {
            let r = RecurrenceRule(raw)
            #expect(r.isCustom && r.raw == raw)
        }
    }
    @Test func customFieldsAreRead() {
        let r = RecurrenceRule("custom:monthly:2:onthe:third:monday")
        #expect(r.frequency == .monthly && r.every == 2 && r.monthMode == .onThe(ordinal: "third", weekday: "monday"))
        #expect(RecurrenceRule("custom:daily:5").every == 5)
    }
    @Test func unknownRuleBecomesCustomDailyNotACrash() {
        #expect(RecurrenceRule("nonsense").raw == "custom:daily:1")
        #expect(RecurrenceRule("custom:hourly:2").raw == "custom:daily:1")
    }
    @Test func everyIsKeptInRange() {
        #expect(RecurrenceRule(custom: .daily, every: 0).every == 1)
        #expect(RecurrenceRule(custom: .daily, every: 500).every == 99)
    }
    @Test func monthModeIsOnlyWrittenForMonthly() {
        var r = RecurrenceRule(custom: .weekly, every: 2, monthMode: .each(day: 9))
        #expect(r.raw == "custom:weekly:2")
        r.frequency = .monthly
        #expect(r.raw == "custom:monthly:2:each:9")
    }
}
