import Foundation
import Testing
@testable import ObeloShared

func makeSuggestion(_ type: String, title: String? = "Something", _ edit: (inout CaptureSuggestion) -> Void = { _ in }) -> CaptureSuggestion {
    var obj: [String: Any] = ["type": type]
    if let title { obj["title"] = title }
    var s = try! JSONDecoder().decode(CaptureSuggestion.self, from: JSONSerialization.data(withJSONObject: obj))
    edit(&s)
    return s
}

@MainActor
final class StubCaptureAPI: CaptureAPI {
    struct Failure: LocalizedError { var errorDescription: String? { "Stub failure" } }
    var calls: [String] = []
    var failNext = false
    var answer = CaptureDraft(draftId: 7, suggestion: makeSuggestion("task"))
    var lastBody: [String: Any] = [:]
    var lastType: String?

    private func record(_ s: String) throws { calls.append(s); if failNext { failNext = false; throw Failure() } }

    func process(raw: String, type: String?) async throws -> CaptureDraft { try record("process \(raw)"); lastType = type; return answer }
    func confirm(draftId: Int, body: [String: Any]) async throws -> CaptureSaved {
        try record("confirm \(draftId)"); lastBody = body
        return CaptureSaved(type: body["type"] as? String ?? "note", id: 42)
    }
    func reject(draftId: Int) async throws { try record("reject \(draftId)") }
    func allTags() async throws -> [String] { try record("tags"); return ["work", "home"] }
}

@MainActor
struct CaptureStoreTests {
    func store() -> (CaptureStore, StubCaptureAPI) {
        let api = StubCaptureAPI()
        return (CaptureStore(api: api), api)
    }

    @Test func eachTypeHasTheFieldsTheWebShows() {
        typealias F = CaptureTypes.Field
        #expect(CaptureTypes.fields(for: "task") == [.title, .tags, .content, .dueDate, .dueTime, .priority])
        #expect(CaptureTypes.fields(for: "reminder") == CaptureTypes.fields(for: "task"))
        #expect(CaptureTypes.fields(for: "note") == [.title, .tags, .content, .source, .author])
        #expect(CaptureTypes.fields(for: "journal") == CaptureTypes.fields(for: "note"))
        #expect(CaptureTypes.fields(for: "quote") == CaptureTypes.fields(for: "note"))
        #expect(CaptureTypes.fields(for: "list") == [.title, .tags, .items])
        #expect(CaptureTypes.fields(for: "bookmark") == [.title, .tags, .url, .content])
        #expect(CaptureTypes.titleLabel("quote") == "Quote / Book title" && CaptureTypes.titleLabel("task") == "Title")
        #expect(CaptureTypes.contentLabel("bookmark") == "Description" && CaptureTypes.contentLabel("task") == "Notes")
    }

    @Test func processTrimsTheTextAndShowsTheSuggestionAndTags() async {
        let (s, api) = store()
        s.raw = "  call the dentist  "
        await s.process()
        #expect(api.calls == ["process call the dentist", "tags"])
        #expect(s.draft?.draftId == 7 && s.allTags == ["work", "home"] && s.error == nil)
    }

    @Test func processDoesNothingForEmptyText() async {
        let (s, api) = store()
        s.raw = "   \n "
        #expect(!s.canProcess)
        await s.process()
        #expect(api.calls.isEmpty && s.draft == nil)
    }

    @Test func aFailedProcessKeepsTheTextAndSetsAnError() async {
        let (s, api) = store()
        s.raw = "buy milk"
        api.failNext = true
        await s.process()
        #expect(s.draft == nil && s.raw == "buy milk" && s.error == "Stub failure" && !s.processing)
    }

    @Test func taskBodyHasDatesAndPriorityButNotSourceOrItems() async {
        let s = makeSuggestion("task", title: "  Call the dentist ") {
            $0.dueDate = "2026-11-17"; $0.dueTime = "15:00"; $0.priority = "high"; $0.content = "Ask about the crown"
            $0.source = "ignored"; $0.items = ["ignored"]; $0.tags = [" Health ", "health", "", "Home"]
        }
        let body = CaptureStore.confirmBody(s)
        #expect(body["type"] as? String == "task" && body["title"] as? String == "Call the dentist")
        #expect(body["dueDate"] as? String == "2026-11-17" && body["dueTime"] as? String == "15:00" && body["priority"] as? String == "high")
        #expect(body["content"] as? String == "Ask about the crown")
        #expect(body["tags"] as? [String] == ["health", "home"])
        #expect(body["source"] == nil && body["items"] == nil)
    }

    @Test func noteBodyHasSourceAndAuthorButNoDates() async {
        let s = makeSuggestion("quote", title: "Four Thousand Weeks") {
            $0.source = "Book"; $0.author = "Oliver Burkeman"; $0.dueDate = "2026-11-17"
        }
        let body = CaptureStore.confirmBody(s)
        #expect(body["source"] as? String == "Book" && body["author"] as? String == "Oliver Burkeman")
        #expect(body["dueDate"] == nil && body["priority"] == nil)
    }

    @Test func listBodyHasCleanedItemsAndNoContent() async {
        let s = makeSuggestion("list", title: "Groceries") { $0.items = ["Milk", "  ", " Eggs ", ""]; $0.content = "ignored" }
        let body = CaptureStore.confirmBody(s)
        #expect(body["items"] as? [String] == ["Milk", "Eggs"] && body["content"] == nil)
    }

    @Test func bookmarkBodyHasTheURL() async {
        let s = makeSuggestion("bookmark", title: "React docs") { $0.url = " https://react.dev " }
        #expect(CaptureStore.confirmBody(s)["url"] as? String == "https://react.dev")
    }

    @Test func emptyFieldsAreLeftOut() async {
        let s = makeSuggestion("task", title: "Only a title") { $0.content = "   "; $0.priority = "" }
        let body = CaptureStore.confirmBody(s)
        #expect(body["content"] == nil && body["priority"] == nil && body["dueDate"] == nil)
    }

    @Test func canSaveNeedsATitleAndABookmarkNeedsAURL() async {
        let (s, _) = store()
        #expect(!s.canSave)                                   // nothing on screen
        s.adopt(CaptureDraft(draftId: 1, suggestion: makeSuggestion("task", title: "  ")))
        #expect(!s.canSave)
        s.suggestion?.title = "Buy milk"
        #expect(s.canSave)
        s.suggestion?.type = "bookmark"
        #expect(!s.canSave)
        s.suggestion?.url = "https://example.com"
        #expect(s.canSave)
    }

    @Test func savingSendsTheEditedFieldsAndClearsTheBoxAndSuggestion() async {
        let (s, api) = store()
        s.raw = "remind me to call"
        await s.process()
        s.suggestion?.type = "reminder"
        s.suggestion?.title = "Call the dentist"
        let saved = await s.save()
        #expect(saved == CaptureSaved(type: "reminder", id: 42))
        #expect(api.calls.last == "confirm 7" && api.lastBody["type"] as? String == "reminder")
        #expect(s.draft == nil && s.raw.isEmpty && !s.saving)
    }

    @Test func aRefusedSaveKeepsTheSuggestionAndEverythingTyped() async {
        let (s, api) = store()
        s.raw = "x"
        await s.process()
        s.suggestion?.title = "Edited title"
        api.failNext = true
        let saved = await s.save()
        #expect(saved == nil && s.error == "Stub failure")
        #expect(s.draft != nil && s.suggestion?.title == "Edited title" && s.raw == "x")
    }

    @Test func discardGoesBackToTheBoxWithTheTextStillThere() async {
        let (s, api) = store()
        s.raw = "something"
        await s.process()
        await s.discard()
        #expect(s.draft == nil && s.raw == "something" && api.calls.last == "reject 7")
    }

    @Test func prefillFillsTheBoxButNeverOverAReviewedSuggestion() async {
        let (s, _) = store()
        s.prefill("from today")
        #expect(s.raw == "from today")
        s.raw = "typed"
        await s.process()
        s.prefill("ignored")
        #expect(s.raw == "typed")
    }

    @Test func aChosenTypeIsSentAndAutoSendsNothing() async {
        let (s, api) = store()
        s.raw = "take out the trash at 10am"
        await s.process()
        #expect(api.lastType == nil)
        s.chosenType = "task"
        await s.process()
        #expect(api.lastType == "task")
    }

    @Test func theChosenTypeWinsEvenWhenTheServerAnswersWithAnother() async {
        let (s, api) = store()
        api.answer = CaptureDraft(draftId: 7, suggestion: makeSuggestion("reminder", title: "Take out the trash") {
            $0.dueDate = "2026-11-16"; $0.dueTime = "10:00"
        })
        s.raw = "take out the trash at 10am"
        s.chosenType = "task"
        await s.process()
        #expect(s.suggestion?.type == "task" && s.suggestion?.dueTime == "10:00" && s.suggestion?.title == "Take out the trash")
        let body = CaptureStore.confirmBody(s.suggestion!)
        #expect(body["type"] as? String == "task" && body["dueTime"] as? String == "10:00")
    }

    @Test func autoLeavesTheServersTypeAlone() async {
        let (s, api) = store()
        api.answer = CaptureDraft(draftId: 7, suggestion: makeSuggestion("reminder"))
        s.raw = "x"
        await s.process()
        #expect(s.suggestion?.type == "reminder")
    }

    @Test func savingGoesBackToAuto() async {
        let (s, _) = store()
        s.raw = "x"
        s.chosenType = "list"
        await s.process()
        await s.save()
        #expect(s.chosenType == nil)
    }

    @Test func discardingKeepsTheChosenType() async {
        let (s, _) = store()
        s.raw = "x"
        s.chosenType = "note"
        await s.process()
        await s.discard()
        #expect(s.chosenType == "note")
    }
}
