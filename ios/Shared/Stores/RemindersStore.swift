import SwiftUI

// The Reminders module's logic, with no interface: the four tabs, the tag filter, selection, the open
// reminder, create / edit, complete / restore / snooze / delete and the bulk actions. The Mac screen is
// built on it. It talks to the server through `RemindersAPI`, so tests can use a stub.

struct RemindersListResponse: Decodable, Equatable {
    let reminders: [ReminderItem]
    let tags: [String]
    let counts: Counts
    struct Counts: Decodable, Equatable { let overdue: Int; let today: Int }
}

/// Every field of a reminder the detail pane edits. Sent whole on each save, like the web form.
/// A reminder needs a title, a date and a time (`isComplete`).
struct ReminderDraft: Equatable {
    var title = ""
    var notes = ""
    var dueDate = ""
    var dueTime = ""
    /// Minutes before the due time that the notification goes out: 0, 15, 30 or 60
    var reminderOffset = 0
    var priority = "none"
    var tags: [String] = []
    var recurring = false
    var recurRule = "daily"

    init() {}
    init(_ r: ReminderItem) {
        title = r.title; notes = r.notes; dueDate = r.dueDate ?? ""; dueTime = r.dueTime ?? ""
        reminderOffset = r.reminderOffset ?? 0; priority = r.priority; tags = r.tags
        recurring = r.recurring; recurRule = r.recurRule ?? "daily"
    }

    /// A blank reminder for "New reminder": today, the next full hour, notify at the due time
    static func blank(now: Date = Date(), in tz: TimeZone = .current) -> ReminderDraft {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        let hourStart = cal.dateInterval(of: .hour, for: now)?.start ?? now
        let due = cal.date(byAdding: .hour, value: 1, to: hourStart) ?? now
        var d = ReminderDraft()
        d.dueDate = Fmt.ymd(due, in: tz)
        let c = cal.dateComponents([.hour, .minute], from: due)
        d.dueTime = String(format: "%02d:%02d", c.hour ?? 9, c.minute ?? 0)
        return d
    }

    var isComplete: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty && !dueDate.isEmpty && !dueTime.isEmpty
    }

    var body: [String: Any] {
        ["title": title, "notes": notes, "dueDate": dueDate, "dueTime": dueTime, "reminderOffset": reminderOffset,
         "priority": priority, "tags": tags, "recurring": recurring, "recurRule": recurRule]
    }
}

@MainActor
protocol RemindersAPI {
    func list(view: String, tag: String?) async throws -> RemindersListResponse
    func detail(id: Int) async throws -> ReminderItem
    func create(_ body: [String: Any]) async throws -> ReminderItem
    func update(id: Int, _ body: [String: Any]) async throws -> ReminderItem
    func complete(id: Int) async throws
    func restore(id: Int) async throws
    func delete(id: Int) async throws
    func snooze(id: Int, duration: String) async throws
    /// Returns how many reminders the server changed
    func bulk(action: String, ids: [Int]) async throws -> Int
    func allTags() async throws -> [String]
}

@MainActor
struct LiveRemindersAPI: RemindersAPI {
    private var api: APIClient { .shared }
    private struct One: Decodable { let reminder: ReminderItem }
    private struct Count: Decodable { let count: Int }
    private struct Tags: Decodable { let tags: [String] }

    func list(view: String, tag: String?) async throws -> RemindersListResponse {
        try await api.get("/reminders", query: ["view": view, "tag": tag])
    }
    func detail(id: Int) async throws -> ReminderItem { (try await api.get("/reminders/\(id)") as One).reminder }
    func create(_ body: [String: Any]) async throws -> ReminderItem { (try await api.post("/reminders", body) as One).reminder }
    func update(id: Int, _ body: [String: Any]) async throws -> ReminderItem {
        (try await api.post("/reminders/\(id)", body, method: "PUT") as One).reminder
    }
    func complete(id: Int) async throws { try await api.post("/reminders/\(id)/complete") }
    func restore(id: Int) async throws { try await api.post("/reminders/\(id)/restore") }
    func delete(id: Int) async throws { try await api.delete("/reminders/\(id)") }
    func snooze(id: Int, duration: String) async throws { try await api.post("/reminders/\(id)/snooze", ["duration": duration]) }
    func bulk(action: String, ids: [Int]) async throws -> Int {
        (try await api.post("/reminders/bulk", ["action": action, "ids": ids]) as Count).count
    }
    func allTags() async throws -> [String] { (try await api.get("/tags") as Tags).tags }
}

@MainActor @Observable
final class RemindersStore {
    static let views = ["upcoming", "today", "overdue", "completed"]
    static let viewLabels = ["upcoming": "Upcoming", "today": "Today", "overdue": "Overdue", "completed": "Completed"]
    static let priorities = ["none", "low", "medium", "high"]
    static let snoozes: [(String, String)] = [("15min", "15 min"), ("1hour", "1 hour"), ("tomorrow", "Tomorrow")]

    private let api: RemindersAPI

    var view = "upcoming"
    var tag: String?
    private(set) var reminders: [ReminderItem] = []
    private(set) var tagList: [String] = []
    private(set) var counts = RemindersListResponse.Counts(overdue: 0, today: 0)
    private(set) var loaded = false
    var error: String?

    /// Ticked or ⌘/⇧-clicked rows. One id shows that reminder in the detail pane.
    var selection: Set<Int> = []
    /// The reminder in the detail pane, when exactly one row is selected
    private(set) var open: ReminderItem?
    private(set) var allTags: [String] = []

    init(api: RemindersAPI) { self.api = api }
    convenience init() { self.init(api: LiveRemindersAPI()) }

    var isFiltered: Bool { tag != nil }

    // ── List ────────────────────────────────────────────────────────────────

    func load() async {
        do {
            let r = try await api.list(view: view, tag: tag)
            reminders = r.reminders; tagList = r.tags; counts = r.counts; loaded = true; error = nil
            selection = selection.filter { id in r.reminders.contains { $0.id == id } }
            if selection.count != 1 { open = nil }
        } catch { self.error = error.localizedDescription }
    }

    func show(view: String) async { self.view = view; selection = []; open = nil; await load() }
    func toggleTag(_ t: String) async { tag = (tag == t) ? nil : t; await load() }
    func clearFilter() async { tag = nil; await load() }

    /// The tab a reminder is in, to show it from another screen (a click on a reminder in Today)
    static func view(for r: ReminderItem) -> String {
        if r.completed { return "completed" }
        return r.dueState == "overdue" ? "overdue" : "upcoming"
    }

    // ── One reminder ────────────────────────────────────────────────────────

    func select(_ ids: Set<Int>) async {
        selection = ids
        guard ids.count == 1, let id = ids.first else { open = nil; return }
        await openReminder(id)
    }

    func openReminder(_ id: Int) async {
        do {
            let r = try await api.detail(id: id)
            guard selection == [id] else { return }   // the person moved on while it loaded
            open = r
            if allTags.isEmpty { allTags = (try? await api.allTags()) ?? [] }
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    /// Creates a reminder from the full set of fields ("Add reminder"); returns it so the screen can select it
    @discardableResult
    func create(_ draft: ReminderDraft) async -> ReminderItem? {
        guard draft.isComplete else { error = "Title, date, and time are required."; return nil }
        do {
            let r = try await api.create(draft.body)
            error = nil
            return r
        } catch { self.error = error.localizedDescription; return nil }
    }

    /// Saves every field of the open reminder. The row is updated in place; it moves tab at the next load.
    @discardableResult
    func save(_ id: Int, _ draft: ReminderDraft) async -> Bool {
        guard draft.isComplete else { return false }
        do {
            let r = try await api.update(id: id, draft.body)
            if let i = reminders.firstIndex(where: { $0.id == id }) { reminders[i] = r }
            if open?.id == id { open = r }
            await refreshCounts()
            error = nil
            return true
        } catch { self.error = error.localizedDescription; return false }
    }

    /// A completed repeating reminder makes its next one, so the list is loaded again; the others just leave it
    func complete(_ id: Int) async { await change { try await self.api.complete(id: id) }; dropFromSelection([id]) }
    func restore(_ id: Int) async { await change { try await self.api.restore(id: id) }; dropFromSelection([id]) }
    func delete(_ id: Int) async { await change { try await self.api.delete(id: id) }; dropFromSelection([id]) }
    func snooze(_ id: Int, _ duration: String) async { await change { try await self.api.snooze(id: id, duration: duration) } }

    // ── Several at once ─────────────────────────────────────────────────────

    /// Mark complete and Delete; on Completed only Delete (the web's bulk bar)
    var bulkChoices: [(String, String)] {
        view == "completed" ? [("delete", "Delete")] : [("complete", "Mark complete"), ("delete", "Delete")]
    }

    /// Applies `action` to the selected reminders with one request. Returns how many the server changed.
    @discardableResult
    func applyBulk(_ action: String) async -> Int {
        let ids = Array(selection)
        guard !ids.isEmpty else { return 0 }
        do {
            let n = try await api.bulk(action: action, ids: ids)
            selection = []; open = nil
            await load()
            return n
        } catch { self.error = error.localizedDescription; return 0 }
    }

    /// One reminder from the server, without opening it (to find out which tab it belongs in)
    func fetch(_ id: Int) async -> ReminderItem? { try? await api.detail(id: id) }

    /// The tags to suggest in the tag picker, fetched once
    func loadAllTags() async {
        if allTags.isEmpty { allTags = (try? await api.allTags()) ?? [] }
    }

    // ── Internals ───────────────────────────────────────────────────────────

    private func change(_ call: () async throws -> Void) async {
        do { try await call(); error = nil; await load() }
        catch { self.error = error.localizedDescription }
    }

    private func dropFromSelection(_ ids: [Int]) {
        selection.subtract(ids)
        if let o = open, ids.contains(o.id) { open = nil }
    }

    /// The tab badges, after an edit. A failed refresh keeps the old numbers.
    private func refreshCounts() async {
        if let r = try? await api.list(view: view, tag: tag) { counts = r.counts; tagList = r.tags }
    }
}
