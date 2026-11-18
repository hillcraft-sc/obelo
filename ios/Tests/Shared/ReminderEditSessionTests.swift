import Testing
@testable import ObeloShared

@MainActor
struct ReminderEditSessionTests {
    func make(delay: Duration = .milliseconds(30)) async -> (ReminderEditSession, StubRemindersAPI, RemindersStore) {
        let api = StubRemindersAPI([makeReminder(1, title: "Old"), makeReminder(2)])
        let store = RemindersStore(api: api)
        await store.load()
        return (ReminderEditSession(reminder: api.reminders[0], store: store, delay: delay), api, store)
    }

    @Test func flushSendsTheWholeDraftOnce() async {
        let (s, api, _) = await make()
        s.draft.title = "New"
        s.draft.priority = "high"
        s.draft.reminderOffset = 30
        await s.flush()
        #expect(api.calls.filter { $0.hasPrefix("update") } == ["update 1"])
        #expect(api.lastBody["title"] as? String == "New")
        #expect(api.lastBody["priority"] as? String == "high")
        #expect(api.lastBody["reminderOffset"] as? Int == 30)
        #expect(api.lastBody["dueTime"] as? String == "09:00")
        #expect(s.state == .saved && !s.isDirty)
    }

    @Test func nothingChangedMeansNoCall() async {
        let (s, api, _) = await make()
        await s.flush()
        #expect(!api.calls.contains { $0.hasPrefix("update") })
        #expect(s.state == .idle)
    }

    @Test func aChangeSavesByItselfAfterTheDelay() async throws {
        let (s, api, _) = await make(delay: .milliseconds(20))
        s.draft.title = "Auto"
        try await Task.sleep(for: .milliseconds(200))
        #expect(api.calls.contains("update 1"))
        #expect(s.state == .saved)
    }

    @Test func manyQuickEditsMakeOneSave() async throws {
        let (s, api, _) = await make(delay: .milliseconds(60))
        for c in ["a", "ab", "abc"] { s.draft.title = c; try await Task.sleep(for: .milliseconds(10)) }
        try await Task.sleep(for: .milliseconds(250))
        #expect(api.calls.filter { $0.hasPrefix("update") }.count == 1)
        #expect(api.lastBody["title"] as? String == "abc")
    }

    @Test func aMissingTitleOrTimeIsNotSentAndGoesBackWhenYouLeave() async {
        let (s, api, _) = await make()
        s.draft.title = ""
        await s.flush()
        #expect(!api.calls.contains { $0.hasPrefix("update") })
        await s.flush(leaving: true)
        #expect(s.draft.title == "Old")
        s.draft.dueTime = ""
        await s.flush(leaving: true)
        #expect(s.draft.dueTime == "09:00")
        #expect(!api.calls.contains { $0.hasPrefix("update") })
    }

    @Test func aFailedSaveShowsFailedAndKeepsTheDraft() async {
        let (s, api, _) = await make()
        s.draft.title = "Changed"
        api.failNext = true
        await s.flush()
        #expect(s.state == .failed)
        #expect(s.draft.title == "Changed" && s.isDirty)
    }

    @Test func adoptTakesAChangeFromElsewhereOnlyWhenThereAreNoEdits() async {
        let (s, _, _) = await make()
        s.adopt(makeReminder(1, title: "Elsewhere"))
        #expect(s.draft.title == "Elsewhere" && !s.isDirty)
        s.draft.title = "Mine"
        s.adopt(makeReminder(1, title: "Other"))
        #expect(s.draft.title == "Mine")
    }

    @Test func escapePutsAFieldBack() async {
        let (s, _, _) = await make()
        s.draft.title = "Typing"
        s.revert(\.title)
        #expect(s.draft.title == "Old")
    }
}
