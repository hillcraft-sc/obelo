import Foundation
import Testing
@testable import ObeloShared

func makeRoutineItem(_ id: Int, title: String = "Routine", tod: String = "morning", due: Bool = true, done: Bool = false,
                     active: Bool = true, frequency: String = "daily", days: [String] = [], duration: Int? = nil,
                     count: Int = 0, finished: Bool? = nil, streak: Int = 0, tags: [String] = []) -> Routine {
    var obj: [String: Any] = [
        "id": id, "title": title, "description": "", "timeOfDay": tod, "frequency": frequency, "scheduleDays": days,
        "streakCurrent": streak, "streakBest": streak, "tags": tags, "notify": false, "active": active,
        "completionCount": count, "completedToday": done, "dueToday": due,
    ]
    if let duration { obj["durationDays"] = duration }
    if let finished { obj["finishedChallenge"] = finished }
    return try! JSONDecoder().decode(Routine.self, from: JSONSerialization.data(withJSONObject: obj))
}

/// A fake server: routines in memory, a log of calls, and a switch to make the next call fail
@MainActor
final class StubRoutinesAPI: RoutinesAPI {
    struct Failure: LocalizedError { var errorDescription: String? { "Stub failure" } }
    var routines: [Routine]
    var calls: [String] = []
    var failNext = false
    var lastBody: [String: Any] = [:]
    var nextId = 100

    init(_ routines: [Routine] = []) { self.routines = routines }

    private func record(_ s: String) throws { calls.append(s); if failNext { failNext = false; throw Failure() } }

    func list(view: String, tag: String?) async throws -> RoutinesListResponse {
        try record("list \(view) \(tag ?? "-")")
        return RoutinesListResponse(routines: routines.filter { $0.active == (view != "archived") }, tags: ["health"])
    }
    func detail(id: Int) async throws -> RoutineDetail {
        try record("detail \(id)")
        let r = routines.first { $0.id == id } ?? makeRoutineItem(id)
        return RoutineDetail(routine: r, heatmap: [], weeklyStats: [])
    }
    func create(_ body: [String: Any]) async throws -> Routine {
        try record("create"); lastBody = body
        nextId += 1
        let r = makeRoutineItem(nextId, title: body["title"] as? String ?? "")
        routines.append(r)
        return r
    }
    func update(id: Int, _ body: [String: Any]) async throws -> Routine {
        try record("update \(id)"); lastBody = body
        let r = makeRoutineItem(id, title: body["title"] as? String ?? "", tod: body["timeOfDay"] as? String ?? "morning")
        if let i = routines.firstIndex(where: { $0.id == id }) { routines[i] = r }
        return r
    }
    func complete(id: Int) async throws -> Routine {
        try record("complete \(id)")
        guard let i = routines.firstIndex(where: { $0.id == id }) else { return makeRoutineItem(id) }
        let old = routines[i]
        routines[i] = makeRoutineItem(id, title: old.title, tod: old.timeOfDay, done: !old.completedToday)
        return routines[i]
    }
    func archive(id: Int) async throws {
        try record("archive \(id)")
        if let i = routines.firstIndex(where: { $0.id == id }) { let o = routines[i]; routines[i] = makeRoutineItem(id, title: o.title, active: !o.active) }
    }
    func delete(id: Int) async throws { try record("delete \(id)"); routines.removeAll { $0.id == id } }
    func bulk(action: String, ids: [Int]) async throws -> Int {
        try record("bulk \(action) \(ids.sorted())")
        let n = routines.filter { ids.contains($0.id) }.count
        if action == "delete" { routines.removeAll { ids.contains($0.id) } }
        else { for id in ids { if let i = routines.firstIndex(where: { $0.id == id }) { let o = routines[i]; routines[i] = makeRoutineItem(id, title: o.title, active: action == "restore") } } }
        return n
    }
    func allTags() async throws -> [String] { try record("tags"); return ["health", "home"] }
}

@MainActor
struct RoutinesStoreTests {
    func make(_ items: [Routine]? = nil) async -> (RoutinesStore, StubRoutinesAPI) {
        let api = StubRoutinesAPI(items ?? [
            makeRoutineItem(1, title: "Walk", tod: "morning"), makeRoutineItem(2, title: "Read", tod: "evening"),
            makeRoutineItem(3, title: "Stretch", tod: "morning"), makeRoutineItem(4, title: "Weekly review", tod: "anytime", due: false),
            makeRoutineItem(5, title: "Old habit", active: false),
        ])
        let store = RoutinesStore(api: api)
        await store.load()
        return (store, api)
    }

    @Test func todayGroupsTheRoutinesDueTodayByTimeOfDayAndLeavesEmptyGroupsOut() async {
        let (s, _) = await make()
        #expect(s.dueGroups.map(\.timeOfDay) == ["morning", "evening"])
        #expect(s.dueGroups[0].routines.map(\.id) == [1, 3])
        #expect(s.notDueToday.map(\.id) == [4])
        #expect(s.displayedIDs == [1, 3, 2, 4])
        #expect(s.tagList == ["health"])
    }

    @Test func theAllTabIsOneFlatListOfActiveRoutines() async {
        let (s, api) = await make()
        await s.show(view: "all")
        #expect(api.calls.last == "list today -")
        #expect(s.displayedIDs == [1, 2, 3, 4])
    }

    @Test func theArchivedTabAsksForArchivedAndPicksOutCompletedStreaks() async {
        let (s, api) = await make([
            makeRoutineItem(1, title: "30 days of reading", active: false, duration: 30, count: 30, finished: true, streak: 30),
            makeRoutineItem(2, title: "Stopped", active: false, duration: 30, count: 4, finished: false),
            makeRoutineItem(3, title: "Live"),
        ])
        await s.show(view: "archived")
        #expect(api.calls.last == "list archived -")
        #expect(s.routines.map(\.id) == [1, 2])
        #expect(s.completedStreaks.map(\.id) == [1])
        #expect(s.bulkChoices.map(\.0) == ["restore", "delete"])
        await s.show(view: "today")
        #expect(s.completedStreaks.isEmpty)
        #expect(s.bulkChoices.map(\.0) == ["archive", "delete"])
    }

    @Test func theTagFilterAsksTheServerAndClears() async {
        let (s, api) = await make()
        await s.toggleTag("health")
        #expect(api.calls.last == "list today health")
        #expect(s.isFiltered)
        await s.toggleTag("health")
        #expect(!s.isFiltered)
    }

    @Test func oneSelectedRowOpensItWithItsHeatmapAndSeveralDoNot() async {
        let (s, api) = await make()
        await s.select([2])
        #expect(s.open?.routine.id == 2)
        #expect(api.calls.contains("detail 2"))
        await s.select([1, 2])
        #expect(s.open == nil)
    }

    @Test func markingDoneToggleAndReloadsTheListAndTheOpenRoutine() async {
        let (s, api) = await make()
        await s.select([1])
        await s.toggleToday(1)
        #expect(api.calls.contains("complete 1"))
        #expect(s.routines.first { $0.id == 1 }?.completedToday == true)
        #expect(s.open?.routine.completedToday == true)
        await s.toggleToday(1)
        #expect(s.routines.first { $0.id == 1 }?.completedToday == false)
    }

    @Test func aFailedMarkShowsTheErrorAndChangesNothing() async {
        let (s, api) = await make()
        api.failNext = true
        await s.toggleToday(1)
        #expect(s.error == "Stub failure")
        #expect(s.routines.first { $0.id == 1 }?.completedToday == false)
    }

    @Test func archivingAndDeletingLeaveTheListAndTheSelection() async {
        let (s, api) = await make()
        await s.select([1])
        await s.toggleArchived(1)
        #expect(api.calls.contains("archive 1"))
        #expect(!s.routines.contains { $0.id == 1 })
        #expect(s.selection.isEmpty && s.open == nil)
        await s.delete(2)
        #expect(api.calls.contains("delete 2"))
        #expect(!s.routines.contains { $0.id == 2 })
    }

    @Test func bulkArchiveAndDeleteUseOneRequestEach() async {
        let (s, api) = await make()
        s.selection = [1, 3]
        let n = await s.applyBulk("archive")
        #expect(n == 2)
        #expect(api.calls.filter { $0.hasPrefix("bulk") } == ["bulk archive [1, 3]"])
        #expect(s.selection.isEmpty)
        s.selection = [2]
        _ = await s.applyBulk("delete")
        #expect(api.calls.last(where: { $0.hasPrefix("bulk") }) == "bulk delete [2]")
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

    @Test func aRoutineNeedsATitle() {
        var d = RoutineDraft()
        #expect(!d.isComplete)
        d.title = "  "
        #expect(!d.isComplete)
        d.title = "Walk"
        #expect(d.isComplete)
    }

    @Test func aNewDraftStartsAnytimeDailyOngoingWithoutANotification() {
        let d = RoutineDraft()
        #expect(d.timeOfDay == "anytime" && d.frequency == "daily")
        #expect(d.durationDays == nil && !d.notify && d.specificTime.isEmpty)
    }

    @Test func theBodyKeepsDaysOnlyForWeeklyAndCustomAndDropsTheStartDateWhenOngoing() {
        var d = RoutineDraft()
        d.title = "Run"; d.frequency = "daily"; d.scheduleDays = ["Mon", "Wed"]; d.startDate = "2026-12-01"
        #expect((d.body["scheduleDays"] as? [String]) == [])
        #expect((d.body["startDate"] as? String) == "")
        #expect(d.body["durationDays"] is NSNull)
        d.frequency = "weekly"; d.durationDays = 30
        #expect((d.body["scheduleDays"] as? [String]) == ["Mon", "Wed"])
        #expect((d.body["startDate"] as? String) == "2026-12-01")
        #expect((d.body["durationDays"] as? Int) == 30)
    }

    @Test func createNeedsATitleAndSendsEveryField() async {
        let (s, api) = await make()
        let none = await s.create(RoutineDraft())
        #expect(none == nil)
        #expect(s.error == "Title is required.")
        #expect(!api.calls.contains("create"))
        var d = RoutineDraft()
        d.title = "Meditate"; d.timeOfDay = "evening"; d.tags = ["health"]; d.notify = true; d.specificTime = "21:30"
        let made = await s.create(d)
        #expect(made?.title == "Meditate")
        #expect(api.lastBody["timeOfDay"] as? String == "evening")
        #expect(api.lastBody["notify"] as? Bool == true)
        #expect(api.lastBody["specificTime"] as? String == "21:30")
    }

    @Test func saveUpdatesTheRowAndTheOpenRoutineAndKeepsTodaysState() async {
        let (s, api) = await make()
        await s.select([1])
        var d = RoutineDraft(s.open!.routine)
        d.title = "Renamed"
        let ok = await s.save(1, d)
        #expect(ok)
        #expect(api.calls.contains("update 1"))
        #expect(s.routines.first { $0.id == 1 }?.title == "Renamed")
        #expect(s.routines.first { $0.id == 1 }?.dueToday == true)
        #expect(s.open?.routine.title == "Renamed")
    }

    @Test func aDraftWithNoTitleIsNotSaved() async {
        let (s, api) = await make()
        var d = RoutineDraft(makeRoutineItem(1))
        d.title = ""
        let ok = await s.save(1, d)
        #expect(!ok)
        #expect(!api.calls.contains("update 1"))
    }

    @Test func aTabForARoutineComesFromWhetherItIsArchived() {
        #expect(RoutinesStore.view(for: makeRoutineItem(1)) == "today")
        #expect(RoutinesStore.view(for: makeRoutineItem(1, active: false)) == "archived")
    }
}
