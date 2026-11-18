import Foundation
import Testing
@testable import ObeloShared

func makeTemplate(_ id: String, _ label: String = "Standup", type: String = "note", dateTitle: Bool = false) -> NoteTemplate {
    NoteTemplate(id: id, label: label, type: type, title: "Standup — ", dateTitle: dateTitle, content: "## Done\n- ", startTitle: "Standup — ")
}

@MainActor
final class StubNoteTemplatesAPI: NoteTemplatesAPI {
    struct Failure: LocalizedError { var errorDescription: String? { "Stub failure" } }
    var templates: [NoteTemplate]
    var calls: [String] = []
    var failNext = false
    var lastBody: [String: Any] = [:]
    var nextId = 1

    init(_ templates: [NoteTemplate] = [makeTemplate("meeting", "Meeting Notes"), makeTemplate("weekly", "Weekly Review", type: "journal")]) {
        self.templates = templates
    }

    private func record(_ s: String) throws { calls.append(s); if failNext { failNext = false; throw Failure() } }

    func list() async throws -> [NoteTemplate] { try record("list"); return templates }
    func create(_ body: [String: Any]) async throws -> NoteTemplate {
        try record("create"); lastBody = body
        nextId += 1
        let t = NoteTemplate(id: "t_\(nextId)", label: body["label"] as? String ?? "", type: body["type"] as? String ?? "note",
                             title: body["title"] as? String ?? "", dateTitle: body["dateTitle"] as? Bool ?? false,
                             content: body["content"] as? String ?? "", startTitle: body["title"] as? String ?? "")
        templates.append(t)
        return t
    }
    func update(id: String, _ body: [String: Any]) async throws -> NoteTemplate {
        try record("update \(id)"); lastBody = body
        let i = templates.firstIndex { $0.id == id }!
        templates[i].label = body["label"] as? String ?? templates[i].label
        return templates[i]
    }
    func delete(id: String) async throws { try record("delete \(id)"); templates.removeAll { $0.id == id } }
}

@MainActor
struct NoteTemplatesStoreTests {
    func store(_ templates: [NoteTemplate]? = nil) -> (NoteTemplatesStore, StubNoteTemplatesAPI) {
        let api = templates.map { StubNoteTemplatesAPI($0) } ?? StubNoteTemplatesAPI()
        return (NoteTemplatesStore(api: api), api)
    }

    @Test func loadFillsTheListAndAFailureKeepsItAndSetsAnError() async {
        let (s, api) = store()
        await s.load()
        #expect(s.templates.map(\.id) == ["meeting", "weekly"] && s.loaded && s.error == nil)
        api.failNext = true
        await s.load()
        #expect(s.templates.count == 2 && s.error == "Stub failure")
    }

    @Test func draftsAreCheckedLikeTheServerDoes() {
        var d = NoteTemplateDraft()
        #expect(NoteTemplatesStore.problem(with: d) == "Give the template a name.")
        d.label = "   "
        #expect(NoteTemplatesStore.problem(with: d) != nil)
        d.label = "Standup"
        #expect(NoteTemplatesStore.problem(with: d) == nil)
        d.label = String(repeating: "x", count: 61)
        #expect(NoteTemplatesStore.problem(with: d)?.contains("60") == true)
        d.label = "A"; d.type = "task"
        #expect(NoteTemplatesStore.problem(with: d)?.contains("note, journal or quote") == true)
        d.type = "journal"; d.title = String(repeating: "x", count: 121)
        #expect(NoteTemplatesStore.problem(with: d)?.contains("120") == true)
        d.title = ""; d.content = String(repeating: "x", count: 20001)
        #expect(NoteTemplatesStore.problem(with: d)?.contains("20000") == true)
    }

    @Test func createSendsTheTrimmedFieldsAndAddsTheTemplate() async {
        let (s, api) = store()
        await s.load()
        var d = NoteTemplateDraft()
        d.label = "  Retro  "; d.type = "journal"; d.title = "Retro — "; d.dateTitle = true; d.content = "## Went well"
        let made = await s.create(d)
        #expect(made?.label == "  Retro  ".trimmingCharacters(in: .whitespaces))
        #expect(api.lastBody["label"] as? String == "Retro" && api.lastBody["dateTitle"] as? Bool == true && api.lastBody["type"] as? String == "journal")
        #expect(s.templates.count == 3)
    }

    @Test func aBadDraftIsNotSent() async {
        let (s, api) = store()
        await s.load()
        let made = await s.create(NoteTemplateDraft())
        #expect(made == nil && s.error == "Give the template a name." && !api.calls.contains("create"))
    }

    @Test func createStopsAtTwentyBeforeAskingTheServer() async {
        let (s, api) = store((0..<20).map { makeTemplate("t\($0)") })
        await s.load()
        #expect(s.atLimit)
        var d = NoteTemplateDraft(); d.label = "One more"
        let made = await s.create(d)
        #expect(made == nil && s.error?.contains("at most 20") == true && !api.calls.contains("create"))
    }

    @Test func aRefusedCreateKeepsTheListAndSetsTheError() async {
        let (s, api) = store()
        await s.load()
        api.failNext = true
        var d = NoteTemplateDraft(); d.label = "X"
        #expect(await s.create(d) == nil)
        #expect(s.templates.count == 2 && s.error == "Stub failure")
    }

    @Test func updateReplacesTheTemplateInPlace() async {
        let (s, api) = store()
        await s.load()
        var d = NoteTemplateDraft(s.templates[0]); d.label = "Team meeting"
        #expect(await s.update("meeting", d))
        #expect(s.templates[0].label == "Team meeting" && s.templates.count == 2)
        #expect(api.calls.last == "update meeting")
    }

    @Test func removeDeletesAndAFailureKeepsIt() async {
        let (s, api) = store()
        await s.load()
        api.failNext = true
        await s.remove("meeting")
        #expect(s.templates.count == 2 && s.error == "Stub failure")
        await s.remove("meeting")
        #expect(s.templates.map(\.id) == ["weekly"] && s.error == nil)
    }

    @Test func aDraftStartsFromATemplateAndCarriesItsFields() {
        let d = NoteTemplateDraft(makeTemplate("x", "Retro", type: "journal", dateTitle: true))
        #expect(d.label == "Retro" && d.type == "journal" && d.dateTitle && d.content == "## Done\n- ")
    }
}
