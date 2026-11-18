import Foundation
import Testing
@testable import ObeloShared

private func decode<T: Decodable>(_ json: [String: Any]) -> T {
    let data = try! JSONSerialization.data(withJSONObject: json)
    let d = JSONDecoder()
    d.dateDecodingStrategy = .custom { dec in
        let s = try dec.singleValueContainer().decode(String.self)
        return try Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(s)
    }
    return try! d.decode(T.self, from: data)
}

func makeReminder(_ id: Int, recurring: Bool = false) -> ReminderItem {
    decode(["id": id, "title": "Reminder \(id)", "notes": "", "priority": "none", "tags": [String](), "completed": false,
            "recurring": recurring, "recurLabel": "", "createdAt": "2026-11-14T10:00:00.000Z"])
}

func makeRoutine(_ id: Int, timeOfDay: String = "morning", done: Bool = false) -> Routine {
    decode(["id": id, "title": "Routine \(id)", "description": "", "timeOfDay": timeOfDay, "frequency": "daily",
            "scheduleDays": [String](), "streakCurrent": 0, "streakBest": 0, "tags": [String](), "notify": false,
            "active": true, "completionCount": 0, "completedToday": done, "dueToday": true])
}

func makeDashboard(focus: [TaskItem] = [], due: [Dashboard.DueEntry] = [], routines: [Routine] = [],
                   review: [Dashboard.ReviewNote] = [], slipping: Int = 0,
                   widgets: [(String, Bool)] = [("focus", true), ("calendar", true), ("due_items", true), ("routines", true), ("resurfaced", true), ("review", true)]) -> Dashboard {
    return Dashboard(widgets: widgets.map { Dashboard.Widget(key: $0.0, enabled: $0.1) }, slippingCount: slipping,
                     focusTasks: focus, events: [], due: due, routines: routines, resurfaced: nil, review: review, stale: [])
}

@MainActor
final class StubTodayAPI: TodayAPI {
    struct Failure: LocalizedError { var errorDescription: String? { "Stub failure" } }
    var data: Dashboard
    var calls: [String] = []
    var failNext = false
    var routineAnswer: Routine?

    init(_ data: Dashboard) { self.data = data }

    private func record(_ s: String) throws { calls.append(s); if failNext { failNext = false; throw Failure() } }

    func dashboard() async throws -> Dashboard { try record("dashboard"); return data }
    func completeTask(id: Int) async throws { try record("completeTask \(id)") }
    func completeReminder(id: Int) async throws { try record("completeReminder \(id)") }
    func snoozeReminder(id: Int, duration: String) async throws { try record("snooze \(id) \(duration)") }
    func toggleRoutine(id: Int) async throws -> Routine {
        try record("toggleRoutine \(id)")
        return routineAnswer ?? makeRoutine(id, done: true)
    }
    func markReviewed(noteId: Int) async throws { try record("flag \(noteId)") }
}

@MainActor
struct TodayStoreTests {
    func store(_ d: Dashboard) -> (TodayStore, StubTodayAPI) {
        let api = StubTodayAPI(d)
        return (TodayStore(api: api), api)
    }

    var sample: Dashboard {
        makeDashboard(
            focus: [makeTask(1), makeTask(2)],
            due: [.init(type: "task", overdue: true, task: makeTask(1), reminder: nil),
                  .init(type: "reminder", overdue: false, task: nil, reminder: makeReminder(7)),
                  .init(type: "task", overdue: false, task: makeTask(3), reminder: nil)],
            routines: [makeRoutine(10, timeOfDay: "morning"), makeRoutine(11, timeOfDay: "evening", done: true), makeRoutine(12, timeOfDay: "anytime")],
            review: [.init(id: 50, title: "Old idea", reviewDate: "2026-11-10")],
            slipping: 2)
    }

    @Test func loadFillsTheDataAndClearsAnError() async {
        let (s, api) = store(sample)
        api.failNext = true
        await s.load()
        #expect(!s.loaded && s.error == "Stub failure")
        await s.load()
        #expect(s.loaded && s.error == nil)
        #expect(s.focusTasks.count == 2 && s.slippingCount == 2 && s.due.count == 3)
    }

    @Test func cardsFollowTheUsersOrderAndSkipTheOnesSwitchedOff() async {
        let d = makeDashboard(widgets: [("routines", true), ("focus", true), ("calendar", false), ("review", true)])
        let (s, _) = store(d)
        await s.load()
        #expect(s.cards == ["routines", "focus", "review"])
    }

    @Test func completingATaskRemovesItFromFocusAndDueAtOnce() async {
        let (s, api) = store(sample)
        await s.load()
        await s.complete(task: makeTask(1))
        let dueTaskIDs = s.due.compactMap { $0.task?.id }
        #expect(s.focusTasks.map(\.id) == [2])
        #expect(dueTaskIDs == [3])
        #expect(api.calls.last == "completeTask 1")
    }

    @Test func aRepeatingTaskReloadsSoItsNextDateShows() async {
        let (s, api) = store(sample)
        await s.load()
        var t = makeTask(2)
        t.recurring = true
        await s.complete(task: t)
        #expect(api.calls == ["dashboard", "completeTask 2", "dashboard"])
    }

    @Test func aRefusedCompleteBringsTheRowBackAndSetsAnError() async {
        let (s, api) = store(sample)
        await s.load()
        api.failNext = true
        await s.complete(task: makeTask(1))
        #expect(s.focusTasks.map(\.id) == [1, 2])
        #expect(s.due.count == 3)
        #expect(s.error == "Stub failure")
    }

    @Test func completingAReminderRemovesIt() async {
        let (s, api) = store(sample)
        await s.load()
        await s.complete(reminder: makeReminder(7))
        let dueReminderIDs = s.due.compactMap { $0.reminder?.id }
        #expect(dueReminderIDs.isEmpty)
        #expect(api.calls.last == "completeReminder 7")
    }

    @Test func snoozingRemovesTheReminderAndSaysSo() async {
        let (s, api) = store(sample)
        await s.load()
        await s.snooze(makeReminder(7), "1hour")
        #expect(s.due.count == 2 && s.notice == "Snoozed 1 hour")
        #expect(api.calls.last == "snooze 7 1hour")
        s.notice = nil
        await s.snooze(makeReminder(7), "tomorrow")
        #expect(s.notice == "Snoozed until tomorrow")
    }

    @Test func aFailedSnoozeKeepsTheReminderAndGivesNoNotice() async {
        let (s, api) = store(sample)
        await s.load()
        api.failNext = true
        await s.snooze(makeReminder(7), "1hour")
        #expect(s.due.count == 3 && s.notice == nil && s.error != nil)
    }

    @Test func tickingARoutineFlipsItAndTakesTheServersRow() async {
        let (s, api) = store(sample)
        await s.load()
        api.routineAnswer = makeRoutine(10, timeOfDay: "morning", done: true)
        await s.toggle(routine: makeRoutine(10))
        let ticked = s.routines.first { $0.id == 10 }
        #expect(ticked?.completedToday == true)
        #expect(s.routinesDone == 2)
        #expect(api.calls.last == "toggleRoutine 10")
    }

    @Test func aFailedRoutineTickPutsItBack() async {
        let (s, api) = store(sample)
        await s.load()
        api.failNext = true
        await s.toggle(routine: makeRoutine(10))
        let unticked = s.routines.first { $0.id == 10 }
        #expect(unticked?.completedToday == false)
        #expect(s.error == "Stub failure")
    }

    @Test func routineGroupsAreInTimeOrderAndTheAnytimeHeadingNeedsAnotherGroup() async {
        let (s, _) = store(sample)
        await s.load()
        #expect(s.routineGroups.map(\.timeOfDay) == ["morning", "evening", "anytime"])
        #expect(s.showsAnytimeHeading)
        let (only, _) = store(makeDashboard(routines: [makeRoutine(1, timeOfDay: "anytime"), makeRoutine(2, timeOfDay: "whenever")]))
        await only.load()
        #expect(only.routineGroups.map(\.timeOfDay) == ["anytime"])
        let anytimeCount = only.routineGroups.first?.routines.count
        #expect(anytimeCount == 2)   // an unknown time of day goes under anytime
        #expect(!only.showsAnytimeHeading)
    }

    @Test func markingANoteReviewedRemovesIt() async {
        let (s, api) = store(sample)
        await s.load()
        await s.markReviewed(.init(id: 50, title: "Old idea", reviewDate: nil))
        #expect(s.review.isEmpty && s.needsReviewCount == 0)
        #expect(api.calls.last == "flag 50")
    }
}
