import Testing
@testable import ObeloShared

@MainActor
struct TaskEditSessionTests {
    func make(delay: Duration = .milliseconds(30)) async -> (TaskEditSession, StubTasksAPI, TasksStore) {
        let api = StubTasksAPI([makeTask(1, title: "Old"), makeTask(2)])
        let store = TasksStore(api: api)
        await store.load()
        return (TaskEditSession(task: api.tasks[0], store: store, delay: delay), api, store)
    }

    @Test func flushSendsTheWholeDraftOnce() async {
        let (s, api, _) = await make()
        s.draft.title = "New"
        s.draft.priority = "high"
        await s.flush()
        #expect(api.calls.filter { $0.hasPrefix("update") } == ["update 1"])
        #expect(api.lastBody["title"] as? String == "New")
        #expect(api.lastBody["priority"] as? String == "high")
        #expect(api.lastBody["status"] as? String == "inbox")
        #expect(s.state == .saved && !s.isDirty)
    }

    @Test func flushWithNothingChangedDoesNotCallTheServer() async {
        let (s, api, _) = await make()
        await s.flush()
        #expect(!api.calls.contains { $0.hasPrefix("update") })
        #expect(s.state == .idle)
    }

    @Test func manyQuickEditsMakeOneSaveAfterTheDelay() async throws {
        let (s, api, _) = await make()
        s.draft.title = "N"
        s.draft.title = "Ne"
        s.draft.title = "New"
        #expect(!api.calls.contains { $0.hasPrefix("update") })   // nothing yet
        try await Task.sleep(for: .milliseconds(300))
        #expect(api.calls.filter { $0.hasPrefix("update") }.count == 1)
        #expect(api.lastBody["title"] as? String == "New")
        #expect(s.state == .saved)
    }

    @Test func aFailedSaveKeepsTheDraftAndTheNextFlushRetries() async {
        let (s, api, _) = await make()
        s.draft.title = "New"
        api.failNext = true
        await s.flush()
        #expect(s.state == .failed && s.isDirty && s.draft.title == "New")
        await s.flush()
        #expect(s.state == .saved && !s.isDirty)
    }

    @Test func anEmptyTitleIsNotSavedAndGoesBackWhenLeaving() async {
        let (s, api, _) = await make()
        s.draft.title = "   "
        await s.flush()
        #expect(!api.calls.contains { $0.hasPrefix("update") })
        #expect(s.draft.title == "   ")          // still being edited
        await s.flush(leaving: true)
        #expect(s.draft.title == "Old")
        #expect(!api.calls.contains { $0.hasPrefix("update") })
    }

    @Test func revertPutsOneFieldBack() async {
        let (s, _, _) = await make()
        s.draft.title = "Changed"
        s.draft.notes = "Keep"
        s.revert(\.title)
        #expect(s.draft.title == "Old" && s.draft.notes == "Keep")
    }

    @Test func savingUpdatesTheRowInTheStore() async {
        let (s, _, store) = await make()
        s.draft.title = "Renamed"
        await s.flush()
        #expect(store.tasks.first { $0.id == 1 }?.title == "Renamed")
    }

    @Test func adoptTakesAChangeMadeElsewhereButNotOverUnsavedEdits() async {
        let (s, _, _) = await make()
        s.adopt(makeTask(1, title: "Old", status: "today"))
        #expect(s.draft.status == "today" && !s.isDirty)
        s.draft.notes = "typing"
        s.adopt(makeTask(1, title: "Old", status: "done"))
        #expect(s.draft.status == "today" && s.draft.notes == "typing")
    }
}
