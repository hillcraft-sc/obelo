import SwiftUI

// Note templates (the web's Settings ▸ Notes ▸ Note templates), with no interface: the person's own list,
// and adding, editing and deleting. The same list shows on the web and in every app. A note is started
// from a template by sending its type, starting title and text to the notes API. It talks to the server
// through `NoteTemplatesAPI`, so tests can use a stub.

struct NoteTemplate: Codable, Identifiable, Hashable {
    let id: String
    var label: String
    var type: String
    /// What the person typed for the starting title
    var title: String
    /// "Use today's date as the title"
    var dateTitle: Bool
    var content: String
    /// The title a new note gets, with the date worked out for the person's time zone
    var startTitle: String
}

/// The fields of a template being made or edited
struct NoteTemplateDraft: Equatable {
    var label = ""
    var type = "note"
    var title = ""
    var dateTitle = false
    var content = ""

    init() {}
    init(_ t: NoteTemplate) { label = t.label; type = t.type; title = t.title; dateTitle = t.dateTitle; content = t.content }

    var body: [String: Any] {
        ["label": label.trimmingCharacters(in: .whitespacesAndNewlines), "type": type, "title": title, "dateTitle": dateTitle, "content": content]
    }
}

@MainActor
protocol NoteTemplatesAPI {
    func list() async throws -> [NoteTemplate]
    func create(_ body: [String: Any]) async throws -> NoteTemplate
    func update(id: String, _ body: [String: Any]) async throws -> NoteTemplate
    func delete(id: String) async throws
}

@MainActor
struct LiveNoteTemplatesAPI: NoteTemplatesAPI {
    private var api: APIClient { .shared }
    private struct Many: Decodable { let templates: [NoteTemplate] }
    private struct One: Decodable { let template: NoteTemplate }

    func list() async throws -> [NoteTemplate] { (try await api.get("/note-templates") as Many).templates }
    func create(_ body: [String: Any]) async throws -> NoteTemplate { (try await api.post("/note-templates", body) as One).template }
    func update(id: String, _ body: [String: Any]) async throws -> NoteTemplate {
        (try await api.post("/note-templates/\(id)", body, method: "PATCH") as One).template
    }
    func delete(id: String) async throws { try await api.delete("/note-templates/\(id)") }
}

@MainActor @Observable
final class NoteTemplatesStore {
    static let types = ["note", "journal", "quote"]
    static let typeLabels = ["note": "Note", "journal": "Journal", "quote": "Quote"]
    /// The server's limits, checked here too so a mistake shows before anything is sent
    static let maxCount = 20, maxLabel = 60, maxTitle = 120, maxContent = 20000

    private let api: NoteTemplatesAPI

    private(set) var templates: [NoteTemplate] = []
    private(set) var loaded = false
    var error: String?

    init(api: NoteTemplatesAPI) { self.api = api }
    convenience init() { self.init(api: LiveNoteTemplatesAPI()) }

    var atLimit: Bool { templates.count >= Self.maxCount }

    func load() async {
        do {
            templates = try await api.list()
            loaded = true
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    /// What is wrong with a draft, in words, or nil when it can be saved
    static func problem(with d: NoteTemplateDraft) -> String? {
        let label = d.label.trimmingCharacters(in: .whitespacesAndNewlines)
        if label.isEmpty { return "Give the template a name." }
        if label.count > maxLabel { return "The name can be at most \(maxLabel) characters." }
        if !types.contains(d.type) { return "The type must be note, journal or quote." }
        if d.title.count > maxTitle { return "The starting title can be at most \(maxTitle) characters." }
        if d.content.count > maxContent { return "The starting text can be at most \(maxContent) characters." }
        return nil
    }

    /// Adds a template. Returns it, or nil with `error` set.
    @discardableResult
    func create(_ draft: NoteTemplateDraft) async -> NoteTemplate? {
        if atLimit { error = "You can have at most \(Self.maxCount) templates. Delete one first."; return nil }
        if let p = Self.problem(with: draft) { error = p; return nil }
        do {
            let t = try await api.create(draft.body)
            templates.append(t)
            error = nil
            return t
        } catch { self.error = error.localizedDescription; return nil }
    }

    @discardableResult
    func update(_ id: String, _ draft: NoteTemplateDraft) async -> Bool {
        if let p = Self.problem(with: draft) { error = p; return false }
        do {
            let t = try await api.update(id: id, draft.body)
            if let i = templates.firstIndex(where: { $0.id == id }) { templates[i] = t }
            error = nil
            return true
        } catch { self.error = error.localizedDescription; return false }
    }

    func remove(_ id: String) async {
        do {
            try await api.delete(id: id)
            templates.removeAll { $0.id == id }
            error = nil
        } catch { self.error = error.localizedDescription }
    }
}
