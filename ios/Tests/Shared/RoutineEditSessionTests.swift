import Testing
@testable import ObeloShared

@MainActor
struct RoutineEditSessionTests {
    func make(delay: Duration = .milliseconds(30)) async -> (RoutineEditSession, StubRoutinesAPI, RoutinesStore) {
        let api = StubRoutinesAPI([makeRoutineItem(1, title: "Old"), makeRoutineItem(2)])
        let store = RoutinesStore(api: api)
        await store.load()
        return (RoutineEditSession(routine: api.routines[0], store: store, delay: delay), api, store)
    }

    @Test func flushSendsTheWholeDraftOnce() async {
        let (s, api, _) = await make()
        s.draft.title = "New"
        s.draft.timeOfDay = "evening"
        s.draft.notify = true
        await s.flush()
        #expect(api.calls.filter { $0.hasPrefix("update") } == ["update 1"])
        #expect(api.lastBody["title"] as? String == "New")
        #expect(api.lastBody["timeOfDay"] as? String == "evening")
        #expect(api.lastBody["notify"] as? Bool == true)
        #expect(api.lastBody["frequency"] as? String == "daily")
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

    @Test func anEmptyTitleIsNotSentAndGoesBackWhenYouLeave() async {
        let (s, api, _) = await make()
        s.draft.title = ""
        await s.flush()
        #expect(!api.calls.contains { $0.hasPrefix("update") })
        await s.flush(leaving: true)
        #expect(s.draft.title == "Old")
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
        s.adopt(makeRoutineItem(1, title: "Elsewhere"))
        #expect(s.draft.title == "Elsewhere" && !s.isDirty)
        s.draft.title = "Mine"
        s.adopt(makeRoutineItem(1, title: "Other"))
        #expect(s.draft.title == "Mine")
    }

    @Test func escapePutsAFieldBack() async {
        let (s, _, _) = await make()
        s.draft.title = "Typing"
        s.revert(\.title)
        #expect(s.draft.title == "Old")
    }
}
