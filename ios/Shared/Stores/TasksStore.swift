import SwiftUI

// The Tasks module's logic, with no interface: the list, filters, selection, the open task, quick add,
// complete / restore / delete, bulk actions and subtasks. The Mac screen is built on it. It talks to
// the server through `TasksAPI`, so tests can use a stub.

struct TasksListResponse: Decodable, Equatable {
    let tasks: [TaskItem]
    let tags: [String]
    let counts: Counts
    struct Counts: Decodable, Equatable { let today: Int; let inbox: Int; let slipping: Int }
}

/// Every field of a task the detail pane edits. Sent whole on each save, like the web form.
struct TaskDraft: Equatable {
    var title = ""
    var notes = ""
    var status = "inbox"
    var priority = "none"
    var dueDate: String?
    var dueTime: String?
    var tags: [String] = []
    var recurring = false
    var recurRule = "daily"

    init() {}
    init(_ t: TaskItem) {
        title = t.title; notes = t.notes; status = t.status; priority = t.priority
        dueDate = t.dueDate; dueTime = t.dueTime; tags = t.tags
        recurring = t.recurring; recurRule = t.recurRule ?? "daily"
    }

    var body: [String: Any] {
        ["title": title, "notes": notes, "status": status, "priority": priority,
         "dueDate": dueDate ?? NSNull(), "dueTime": dueTime ?? NSNull(), "tags": tags,
         "recurring": recurring, "recurRule": recurRule]
    }
}

@MainActor
protocol TasksAPI {
    func list(view: String, tag: String?, search: String?) async throws -> TasksListResponse
    func detail(id: Int) async throws -> TaskItem
    func create(_ body: [String: Any]) async throws -> TaskItem
    func update(id: Int, _ body: [String: Any]) async throws -> TaskItem
    func complete(id: Int) async throws
    func restore(id: Int) async throws
    func delete(id: Int) async throws
    func bulk(action: String, ids: [Int]) async throws
    func addSubtask(taskId: Int, title: String) async throws
    func toggleSubtask(taskId: Int, subtaskId: Int) async throws
    func deleteSubtask(taskId: Int, subtaskId: Int) async throws
    func allTags() async throws -> [String]
}

@MainActor
struct LiveTasksAPI: TasksAPI {
    private var api: APIClient { .shared }
    private struct One: Decodable { let task: TaskItem }
    private struct Tags: Decodable { let tags: [String] }

    func list(view: String, tag: String?, search: String?) async throws -> TasksListResponse {
        try await api.get("/tasks", query: ["view": view, "tag": tag, "search": (search?.isEmpty ?? true) ? nil : search])
    }
    func detail(id: Int) async throws -> TaskItem { (try await api.get("/tasks/\(id)") as One).task }
    func create(_ body: [String: Any]) async throws -> TaskItem { (try await api.post("/tasks", body) as One).task }
    func update(id: Int, _ body: [String: Any]) async throws -> TaskItem {
        (try await api.post("/tasks/\(id)", body, method: "PATCH") as One).task
    }
    func complete(id: Int) async throws { try await api.post("/tasks/\(id)/complete") }
    func restore(id: Int) async throws { try await api.post("/tasks/\(id)/restore") }
    func delete(id: Int) async throws { try await api.delete("/tasks/\(id)") }
    func bulk(action: String, ids: [Int]) async throws { try await api.post("/tasks/bulk", ["action": action, "ids": ids]) }
    func addSubtask(taskId: Int, title: String) async throws { try await api.post("/tasks/\(taskId)/subtasks", ["title": title]) }
    func toggleSubtask(taskId: Int, subtaskId: Int) async throws { try await api.post("/tasks/\(taskId)/subtasks/\(subtaskId)/toggle") }
    func deleteSubtask(taskId: Int, subtaskId: Int) async throws { try await api.delete("/tasks/\(taskId)/subtasks/\(subtaskId)") }
    func allTags() async throws -> [String] { (try await api.get("/tags") as Tags).tags }
}

@MainActor @Observable
final class TasksStore {
    static let views = ["inbox", "today", "upcoming", "all", "completed", "archived", "slipping"]
    static let statuses = ["inbox", "today", "in-progress", "done", "archived"]
    static let statusLabels = ["inbox": "Inbox", "today": "Today", "in-progress": "In Progress", "done": "Done", "archived": "Archived"]
    static let priorities = ["none", "low", "medium", "high"]
    static let priorityLabels = ["none": "No priority", "low": "Low", "medium": "Medium", "high": "High"]

    private let api: TasksAPI

    var view = "inbox"
    var tag: String?
    var search = ""
    private(set) var tasks: [TaskItem] = []
    private(set) var tagList: [String] = []
    private(set) var counts = TasksListResponse.Counts(today: 0, inbox: 0, slipping: 0)
    private(set) var loaded = false
    var error: String?

    /// Ticked or ⌘/⇧-clicked rows. One id shows that task in the detail pane.
    var selection: Set<Int> = []
    /// The task in the detail pane (with its subtasks), when exactly one row is selected
    private(set) var open: TaskItem?
    private(set) var allTags: [String] = []

    init(api: TasksAPI) { self.api = api }
    convenience init() { self.init(api: LiveTasksAPI()) }

    var canQuickAdd: Bool { !["completed", "slipping", "archived"].contains(view) }
    var isFiltered: Bool { !search.isEmpty || tag != nil }
    var bulkMode: Bool { selection.count > 1 }

    // ── List ────────────────────────────────────────────────────────────────

    func load() async {
        do {
            let r = try await api.list(view: view, tag: tag, search: search)
            tasks = r.tasks; tagList = r.tags; counts = r.counts; loaded = true; error = nil
            selection = selection.filter { id in r.tasks.contains { $0.id == id } }
            if selection.count != 1 { open = nil }
        } catch { self.error = error.localizedDescription }
    }

    func show(view: String) async { self.view = view; selection = []; open = nil; await load() }
    func toggleTag(_ t: String) async { tag = (tag == t) ? nil : t; await load() }
    func clearFilter() async { tag = nil; search = ""; await load() }

    // ── One task ────────────────────────────────────────────────────────────

    func select(_ ids: Set<Int>) async {
        selection = ids
        guard ids.count == 1, let id = ids.first else { open = nil; return }
        await openTask(id)
    }

    func openTask(_ id: Int) async {
        do {
            let t = try await api.detail(id: id)
            guard selection == [id] else { return }   // the person moved on while it loaded
            open = t
            if allTags.isEmpty { allTags = (try? await api.allTags()) ?? [] }
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    /// Creates a task; returns it so the screen can select it
    @discardableResult
    func quickAdd(_ text: String) async -> TaskItem? {
        let title = text.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return nil }
        do {
            let t = try await api.create(["title": title, "status": view == "today" ? "today" : "inbox"])
            tasks.insert(t, at: 0)
            await refreshCounts()
            error = nil
            return t
        } catch { self.error = error.localizedDescription; return nil }
    }

    /// Creates a task from the full set of fields ("New task")
    @discardableResult
    func create(_ draft: TaskDraft) async -> TaskItem? {
        do {
            let t = try await api.create(draft.body)
            await load()
            return t
        } catch { self.error = error.localizedDescription; return nil }
    }

    /// Saves every field of the open task. The row is updated in place; it leaves the list at the next load.
    @discardableResult
    func save(_ id: Int, _ draft: TaskDraft) async -> Bool {
        do {
            let t = try await api.update(id: id, draft.body)
            replace(t)
            if open?.id == id { open = t.withSubtasks(open?.subtasks) }
            await refreshCounts()
            error = nil
            return true
        } catch { self.error = error.localizedDescription; return false }
    }

    func complete(_ id: Int) async { await run(removing: [id]) { try await self.api.complete(id: id) } }
    func restore(_ id: Int) async { await run(removing: [id]) { try await self.api.restore(id: id) } }
    func delete(_ id: Int) async { await run(removing: [id]) { try await self.api.delete(id: id) } }

    func setStatus(_ id: Int, _ status: String) async {
        guard let t = tasks.first(where: { $0.id == id }) ?? open.flatMap({ $0.id == id ? $0 : nil }) else { return }
        var d = TaskDraft(t); d.status = status
        await save(id, d)
    }

    func setPriority(_ id: Int, _ priority: String) async {
        guard let t = tasks.first(where: { $0.id == id }) ?? open.flatMap({ $0.id == id ? $0 : nil }) else { return }
        var d = TaskDraft(t); d.priority = priority
        await save(id, d)
    }

    // ── Several at once ─────────────────────────────────────────────────────

    static let bulkActions: [(String, String)] = [
        ("complete", "Mark complete"), ("archive", "Archive"), ("restore", "Restore to inbox"),
        ("high", "Priority: High"), ("medium", "Priority: Medium"), ("low", "Priority: Low"), ("none", "Priority: None"),
    ]
    /// Archive on every tab but Archived, where it's Restore (the web's bulk bar)
    var bulkChoices: [(String, String)] {
        Self.bulkActions.filter { view == "archived" ? $0.0 != "archive" : $0.0 != "restore" }
    }

    func applyBulk(_ action: String) async {
        let ids = Array(selection)
        guard !ids.isEmpty else { return }
        do {
            try await api.bulk(action: action, ids: ids)
            selection = []; open = nil
            await load()
        } catch { self.error = error.localizedDescription }
    }

    func deleteSelected() async {
        let ids = Array(selection)
        await run(removing: ids) { for id in ids { try await self.api.delete(id: id) } }
    }

    // ── Subtasks ────────────────────────────────────────────────────────────

    func addSubtask(_ title: String) async {
        let t = title.trimmingCharacters(in: .whitespaces)
        guard let id = open?.id, !t.isEmpty else { return }
        await subtaskCall { try await self.api.addSubtask(taskId: id, title: t) }
    }
    func toggleSubtask(_ sid: Int) async {
        guard let id = open?.id else { return }
        await subtaskCall { try await self.api.toggleSubtask(taskId: id, subtaskId: sid) }
    }
    func deleteSubtask(_ sid: Int) async {
        guard let id = open?.id else { return }
        await subtaskCall { try await self.api.deleteSubtask(taskId: id, subtaskId: sid) }
    }

    // ── Internals ───────────────────────────────────────────────────────────

    private func subtaskCall(_ call: @escaping () async throws -> Void) async {
        guard let id = open?.id else { return }
        do { try await call(); open = try await api.detail(id: id); error = nil }
        catch { self.error = error.localizedDescription }
    }

    private func run(removing ids: [Int], _ call: () async throws -> Void) async {
        do {
            try await call()
            tasks.removeAll { ids.contains($0.id) }
            selection.subtract(ids)
            if let o = open, ids.contains(o.id) { open = nil }
            await refreshCounts()
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    private func replace(_ t: TaskItem) {
        guard let i = tasks.firstIndex(where: { $0.id == t.id }) else { return }
        tasks[i] = t
    }

    /// The tab badges, after a change. A failed refresh keeps the old numbers.
    private func refreshCounts() async {
        if let r = try? await api.list(view: view, tag: tag, search: search) { counts = r.counts; tagList = r.tags }
    }
}

private extension TaskItem {
    func withSubtasks(_ s: [Subtask]?) -> TaskItem { var c = self; if c.subtasks == nil { c.subtasks = s }; return c }
}
