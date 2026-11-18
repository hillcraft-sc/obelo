import Foundation
import SwiftUI

// The global search's logic, with no interface: the typed text, waiting a moment after you stop typing, the
// "at least 2 characters" rule, the results in the server's order, which row is highlighted, the empty and
// failed states, and the words to colour in each title. The Mac palette is built on it. It talks to the server
// through `SearchAPI`, so tests can use a stub.

@MainActor
protocol SearchAPI {
    func search(_ query: String) async throws -> [SearchResponse.Group]
    /// A calendar event by id, so a result can open it in Calendar
    func event(id: Int) async throws -> CalendarEvent
}

@MainActor
struct LiveSearchAPI: SearchAPI {
    private struct One: Decodable { let event: CalendarEvent }
    func search(_ query: String) async throws -> [SearchResponse.Group] {
        (try await APIClient.shared.get("/search", query: ["q": query]) as SearchResponse).results
    }
    func event(id: Int) async throws -> CalendarEvent { (try await APIClient.shared.get("/calendar/events/\(id)") as One).event }
}

/// A piece of a title: matching or not
struct HighlightPiece: Equatable {
    let text: String
    let isMatch: Bool
}

@MainActor @Observable
final class SearchStore {
    enum Phase: Equatable { case hint, searching, results, empty, failed }

    private let api: SearchAPI
    private let delay: Duration
    private var task: Task<Void, Never>?

    private(set) var groups: [SearchResponse.Group] = []
    private(set) var phase: Phase = .hint
    /// The row the keyboard is on, counted across all groups
    private(set) var highlighted = 0

    var query = "" { didSet { if query != oldValue { queryChanged() } } }

    static let minimumLength = 2
    static let hint = "Type at least 2 characters to search"
    static let searching = "Searching…"
    static let failed = "Search failed — please try again."

    init(api: SearchAPI, delay: Duration = .milliseconds(200)) {
        self.api = api
        self.delay = delay
    }
    convenience init() { self.init(api: LiveSearchAPI()) }

    var trimmed: String { query.trimmingCharacters(in: .whitespaces) }

    /// The line the results area shows when there are no rows
    var message: String? {
        switch phase {
        case .hint: Self.hint
        case .searching: groups.isEmpty ? Self.searching : nil
        case .empty: "No results for \"\(trimmed)\""
        case .failed: Self.failed
        case .results: nil
        }
    }

    // ── Typing ──────────────────────────────────────────────────────────────

    private func queryChanged() {
        task?.cancel()
        guard trimmed.count >= Self.minimumLength else {
            groups = []; highlighted = 0; phase = .hint
            return
        }
        // The old rows stay until the new ones arrive
        phase = .searching
        let q = trimmed
        task = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await run(q)
        }
    }

    /// Waits for the search that is under way (for tests)
    func settle() async { await task?.value }

    private func run(_ q: String) async {
        do {
            let result = try await api.search(q)
            guard !Task.isCancelled, q == trimmed else { return }
            groups = result
            highlighted = 0
            phase = result.isEmpty ? .empty : .results
        } catch {
            guard !Task.isCancelled, q == trimmed else { return }
            groups = []; highlighted = 0
            phase = .failed
        }
    }

    /// Forgets the text and the results (the box closing)
    func reset() {
        task?.cancel()
        groups = []; highlighted = 0; phase = .hint
        if !query.isEmpty { query = "" }
    }

    // ── The highlighted row ─────────────────────────────────────────────────

    var hits: [SearchResponse.Hit] { groups.flatMap(\.items) }

    var current: SearchResponse.Hit? { hits.indices.contains(highlighted) ? hits[highlighted] : nil }

    /// ↑ and ↓ stop at the first and last row, as the web does
    func move(_ delta: Int) {
        guard !hits.isEmpty else { return }
        highlighted = min(max(highlighted + delta, 0), hits.count - 1)
    }

    func highlight(_ hit: SearchResponse.Hit) {
        if let i = hits.firstIndex(of: hit) { highlighted = i }
    }

    /// The event behind a Calendar result, so it can be opened; nil when it can't be loaded
    func event(id: Int) async -> CalendarEvent? { try? await api.event(id: id) }

    // ── Wording ─────────────────────────────────────────────────────────────

    /// The title cut into pieces, the words you typed marked (case ignored), as the web's `highlight()`
    static func pieces(of text: String, matching query: String) -> [HighlightPiece] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty, !text.isEmpty else { return text.isEmpty ? [] : [HighlightPiece(text: text, isMatch: false)] }
        var out: [HighlightPiece] = []
        var rest = text[...]
        while let r = rest.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) {
            if r.lowerBound > rest.startIndex { out.append(HighlightPiece(text: String(rest[rest.startIndex..<r.lowerBound]), isMatch: false)) }
            out.append(HighlightPiece(text: String(rest[r]), isMatch: true))
            rest = rest[r.upperBound...]
        }
        if !rest.isEmpty { out.append(HighlightPiece(text: String(rest), isMatch: false)) }
        return out
    }

    /// The group's heading is the server's name; the icon follows the kind
    static func icon(for type: String) -> String {
        ["note": "doc.text", "task": "checkmark.circle", "reminder": "bell", "routine": "arrow.triangle.2.circlepath",
         "calendar": "calendar", "list": "list.bullet", "bookmark": "bookmark"][type] ?? "circle"
    }

    static func spokenKind(_ type: String) -> String {
        ["note": "Note", "task": "Task", "reminder": "Reminder", "routine": "Routine", "calendar": "Event", "list": "List", "bookmark": "Bookmark"][type] ?? type
    }
}
