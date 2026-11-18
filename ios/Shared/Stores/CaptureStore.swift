import SwiftUI

// The Capture page's logic, with no interface: send the text to the server, edit the suggestion that
// comes back, then save it or throw it away. The Mac screen is built on it. It talks to the server
// through `CaptureAPI`, so tests can use a stub.

/// What was saved, so the screen can open it
struct CaptureSaved: Decodable, Equatable {
    let type: String
    let id: Int
}

@MainActor
protocol CaptureAPI {
    /// `type` is a type the person chose before processing; nil lets the AI decide
    func process(raw: String, type: String?) async throws -> CaptureDraft
    func confirm(draftId: Int, body: [String: Any]) async throws -> CaptureSaved
    func reject(draftId: Int) async throws
    func allTags() async throws -> [String]
}

@MainActor
struct LiveCaptureAPI: CaptureAPI {
    private var api: APIClient { .shared }
    private struct Tags: Decodable { let tags: [String] }

    func process(raw: String, type: String?) async throws -> CaptureDraft {
        var body: [String: Any] = ["raw": raw]
        if let type { body["type"] = type }
        return try await api.post("/capture", body)
    }
    func confirm(draftId: Int, body: [String: Any]) async throws -> CaptureSaved { try await api.post("/capture/\(draftId)/confirm", body) }
    func reject(draftId: Int) async throws { try await api.post("/capture/\(draftId)/reject") }
    func allTags() async throws -> [String] { (try await api.get("/tags") as Tags).tags }
}

/// The seven kinds of thing Capture can make, and which fields each one has (web: capture/index.ejs)
enum CaptureTypes {
    enum Field { case url, title, content, items, dueDate, dueTime, priority, tags, source, author }

    static let all = ["task", "reminder", "note", "journal", "quote", "list", "bookmark"]
    static let labels = ["task": "Task", "reminder": "Reminder", "note": "Note", "journal": "Journal",
                         "quote": "Quote", "list": "List", "bookmark": "Bookmark"]
    static let icons = ["task": "✓", "reminder": "🔔", "note": "📝", "journal": "📖", "quote": "💬", "list": "📋", "bookmark": "🔖"]
    static let titleLabels = ["quote": "Quote / Book title", "list": "List name", "bookmark": "Label"]
    static let contentLabels = ["note": "Content", "journal": "Content", "bookmark": "Description"]

    static func label(_ type: String) -> String { labels[type] ?? type.capitalized }
    static func icon(_ type: String) -> String { icons[type] ?? "📝" }
    static func titleLabel(_ type: String) -> String { titleLabels[type] ?? "Title" }
    static func contentLabel(_ type: String) -> String { contentLabels[type] ?? "Notes" }

    static func fields(for type: String) -> Set<Field> {
        var f: Set<Field> = [.title, .tags]
        switch type {
        case "task", "reminder": f.formUnion([.content, .dueDate, .dueTime, .priority])
        case "note", "journal", "quote": f.formUnion([.content, .source, .author])
        case "list": f.insert(.items)
        case "bookmark": f.formUnion([.url, .content])
        default: break
        }
        return f
    }
}

@MainActor @Observable
final class CaptureStore {
    private let api: CaptureAPI

    /// The text box
    var raw = ""
    /// A type the person chose before processing (nil = Auto, the AI decides)
    var chosenType: String?
    /// The suggestion being reviewed, or nil while the box is showing
    private(set) var draft: CaptureDraft?
    private(set) var processing = false
    private(set) var saving = false
    private(set) var allTags: [String] = []
    var error: String?

    init(api: CaptureAPI) { self.api = api }
    convenience init() { self.init(api: LiveCaptureAPI()) }

    var canProcess: Bool { !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !processing }

    /// The suggestion's fields, edited in place
    var suggestion: CaptureSuggestion? {
        get { draft?.suggestion }
        set { if let newValue { draft?.suggestion = newValue } }
    }

    /// A title is needed for every type, and a URL for a bookmark
    var canSave: Bool {
        guard let s = suggestion, !saving else { return false }
        let hasTitle = !(s.title ?? "").trimmingCharacters(in: .whitespaces).isEmpty
        let hasURL = !(s.url ?? "").trimmingCharacters(in: .whitespaces).isEmpty
        return hasTitle && (s.type != "bookmark" || hasURL)
    }

    /// Text sent from Today's Quick Capture. Ignored while a suggestion is being reviewed.
    func prefill(_ text: String) {
        guard draft == nil else { return }
        raw = text
    }

    /// Puts a suggestion on screen (tests and the screen's debug states)
    func adopt(_ draft: CaptureDraft) { self.draft = draft }

    // ── Steps ───────────────────────────────────────────────────────────────

    func process() async {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !processing else { return }
        processing = true
        error = nil
        defer { processing = false }
        do {
            var d = try await api.process(raw: text, type: chosenType)
            // The server is told the choice, but an older server ignores it: the choice wins either way
            if let chosenType, CaptureTypes.all.contains(chosenType), d.suggestion.type != chosenType { d.suggestion.type = chosenType }
            draft = d
            if allTags.isEmpty { allTags = (try? await api.allTags()) ?? [] }
        } catch { self.error = error.localizedDescription }
    }

    /// Saves what's on screen. Returns what was saved, or nil (with `error` set) when the server refused;
    /// the suggestion stays so nothing typed is lost.
    @discardableResult
    func save() async -> CaptureSaved? {
        guard let draft, canSave else { return nil }
        saving = true
        error = nil
        defer { saving = false }
        do {
            let saved = try await api.confirm(draftId: draft.draftId, body: Self.confirmBody(draft.suggestion))
            self.draft = nil
            raw = ""
            chosenType = nil
            return saved
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }

    /// Throws the suggestion away and goes back to the box (the text you typed stays in it)
    func discard() async {
        guard let draft else { return }
        self.draft = nil
        error = nil
        try? await api.reject(draftId: draft.draftId)
    }

    // ── What is sent ────────────────────────────────────────────────────────

    /// Only the fields the chosen type has, with empty ones left out and the tags and list items cleaned
    static func confirmBody(_ s: CaptureSuggestion) -> [String: Any] {
        let fields = CaptureTypes.fields(for: s.type)
        var body: [String: Any] = ["type": s.type]
        func text(_ f: CaptureTypes.Field, _ key: String, _ value: String?) {
            guard fields.contains(f), let v = value?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty else { return }
            body[key] = v
        }
        text(.title, "title", s.title)
        text(.content, "content", s.content)
        text(.url, "url", s.url)
        text(.dueDate, "dueDate", s.dueDate)
        text(.dueTime, "dueTime", s.dueTime)
        text(.priority, "priority", s.priority)
        text(.source, "source", s.source)
        text(.author, "author", s.author)
        if fields.contains(.tags) {
            var seen = Set<String>()
            body["tags"] = (s.tags ?? []).map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty && seen.insert($0).inserted }
        }
        if fields.contains(.items) {
            body["items"] = (s.items ?? []).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
        return body
    }
}
