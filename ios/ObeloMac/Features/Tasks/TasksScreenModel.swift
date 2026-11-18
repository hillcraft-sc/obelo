import AppKit
import SwiftUI

/// Everything the Tasks screen does, so the views only draw and call. The data and the rules are in
/// `TasksStore` and `TaskEditSession` (Shared, tested); this holds the screen's own state: the row
/// selection with its ⌘/⇧ rules, which field should take the cursor, and what waits for a confirmation.
@MainActor @Observable
final class TasksScreenModel {
    let store: TasksStore
    private(set) var session: TaskEditSession?
    var rows = RowSelection<Int>()
    var bulkAction = "complete"
    var quickAddText = ""
    /// Ids waiting for the "Delete this task?" confirmation
    var pendingDelete: [Int]?
    var focusSearch = false
    var focusTitle = false
    var focusQuickAdd = false
    var timeZone: TimeZone = .current

    private var searchTask: Task<Void, Never>?
    private var wantsTitleFocus = false

    init(store: TasksStore = TasksStore()) { self.store = store }

    // ── What's on screen ────────────────────────────────────────────────────

    struct Group: Identifiable { let title: String?; let tasks: [TaskItem]; var id: String { title ?? "" } }

    /// The rows in the order shown. Upcoming is grouped by day: Today, Tomorrow, weekday and date, No date.
    var groups: [Group] {
        guard store.view == "upcoming" else { return [Group(title: nil, tasks: store.tasks)] }
        var order: [String] = []
        var byDay: [String: [TaskItem]] = [:]
        for t in store.tasks {
            let key = t.dueDate ?? ""
            if byDay[key] == nil { order.append(key) }
            byDay[key, default: []].append(t)
        }
        return order.map { Group(title: dayTitle($0), tasks: byDay[$0] ?? []) }
    }

    var displayedIDs: [Int] { groups.flatMap { $0.tasks.map(\.id) } }

    private func dayTitle(_ ymd: String) -> String {
        guard !ymd.isEmpty else { return "No date" }
        let today = Date()
        if ymd == Fmt.ymd(today, in: timeZone) { return "Today" }
        if let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today), ymd == Fmt.ymd(tomorrow, in: timeZone) { return "Tomorrow" }
        return Fmt.weekdayShort(ymd)
    }

    var emptyMessage: String {
        if store.isFiltered { return "No tasks match this filter." }
        switch store.view {
        case "inbox": return "No inbox tasks yet."
        case "today": return "Nothing due today."
        case "upcoming": return "Nothing due in the next 7 days."
        case "completed": return "No completed tasks yet."
        case "archived": return "No archived tasks yet."
        case "slipping": return "No slipping tasks."
        default: return "No tasks yet."
        }
    }

    // ── Loading ─────────────────────────────────────────────────────────────

    func load() async { await store.load(); syncSelection() }

    func show(view: String) async {
        await session?.flush(leaving: true)
        await store.show(view: view)
        rows.clear()
    }

    func toggleTag(_ tag: String) async { await store.toggleTag(tag); syncSelection() }
    func clearFilter() async { await store.clearFilter(); syncSelection() }

    /// Search as you type, after a short pause
    func searchChanged() {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await load()
        }
    }

    private func syncSelection() { rows.set(store.selection) }

    /// "Show this tab and select this task" (a click on a task in Today)
    func handle(_ request: MacRouter.TasksRequest) async {
        await session?.flush(leaving: true)
        if store.isFiltered { store.search = ""; store.tag = nil }
        let view = request.view ?? (request.taskId != nil ? "all" : nil)
        if let view { await show(view: view) } else { await load() }
        guard let id = request.taskId else { return }
        rows = RowSelection()
        rows.click(id, in: [id])
        await store.select([id])
        syncOpen()
    }

    // ── Selection and the open task ─────────────────────────────────────────

    func click(_ id: Int, command: Bool, shift: Bool) {
        rows.click(id, in: displayedIDs, command: command, shift: shift)
        choose(rows.selected)
    }

    /// The row's tick box: adds or removes it from the selection
    func tick(_ id: Int) {
        rows.click(id, in: displayedIDs, command: true)
        choose(rows.selected)
    }

    func arrow(_ delta: Int) {
        rows.step(delta, in: displayedIDs)
        choose(rows.selected)
    }

    func clearSelection() { rows.clear(); choose([]) }

    private func choose(_ ids: Set<Int>) {
        Task {
            await session?.flush(leaving: true)
            await store.select(ids)
            syncOpen()
        }
    }

    /// Makes a new edit session when the open task changed (called when `store.open` changes)
    func syncOpen() {
        guard let open = store.open else { session = nil; return }
        if session?.taskId != open.id {
            session = TaskEditSession(task: open, store: store)
            if wantsTitleFocus {
                wantsTitleFocus = false
                Task { try? await Task.sleep(for: .milliseconds(80)); focusTitle = true }
            }
        }
    }

    /// Saves what's pending (leaving the screen, quitting)
    func leave() async { await session?.flush(leaving: true) }

    // ── Making and changing tasks ───────────────────────────────────────────

    /// "New task": a task in Inbox (Today on the Today tab), opened with its title selected for typing
    func newTask() async {
        await session?.flush(leaving: true)
        if !["inbox", "today", "all"].contains(store.view) { await store.show(view: "inbox") }
        var draft = TaskDraft()
        draft.title = "New task"
        draft.status = store.view == "today" ? "today" : "inbox"
        guard let task = await store.create(draft) else { return }
        wantsTitleFocus = true
        rows = RowSelection()
        rows.click(task.id, in: [task.id])
        await store.select([task.id])
        syncOpen()
    }

    func submitQuickAdd() async {
        let text = quickAddText
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        quickAddText = ""
        if await store.quickAdd(text) == nil { quickAddText = text }
        focusQuickAdd = true
    }

    func complete(_ id: Int) async {
        await store.complete(id)
        await afterChange()
    }

    func restore(_ id: Int) async {
        await store.restore(id)
        await afterChange()
    }

    func setStatus(_ id: Int, _ status: String) async {
        if session?.taskId == id { await session?.flush() }   // pending edits go first, so they aren't overwritten
        await store.setStatus(id, status)
        adoptIntoEditor(id)
    }

    func setPriority(_ id: Int, _ priority: String) async {
        if session?.taskId == id { await session?.flush() }
        await store.setPriority(id, priority)
        adoptIntoEditor(id)
    }

    /// The row's own status and priority are saved from the list; keep the open task's editor in step
    private func adoptIntoEditor(_ id: Int) {
        guard let session, session.taskId == id, let t = store.tasks.first(where: { $0.id == id }) else { return }
        session.adopt(t)
    }

    /// On every tab but All, a finished task leaves the list; on All it stays, shown as done
    private func afterChange() async {
        if store.view == "all" { await store.load() }
        syncSelection()
        syncOpen()
    }

    /// Mark complete (or restore) for the selection, from the menu, ⌘Return or the bar
    func completeSelection() async {
        let ids = Array(rows.selected)
        guard !ids.isEmpty else { return }
        if ids.count == 1, let id = ids.first {
            if store.tasks.first(where: { $0.id == id })?.isDone == true { await restore(id) } else { await complete(id) }
        } else {
            store.selection = rows.selected
            await store.applyBulk("complete")
            rows.clear()
        }
    }

    func applyBulk() async {
        store.selection = rows.selected
        await store.applyBulk(bulkAction)
        rows.clear()
        syncOpen()
    }

    /// A context-menu bulk action on several selected rows
    func bulk(_ action: String) async {
        store.selection = rows.selected
        await store.applyBulk(action)
        rows.clear()
        syncOpen()
    }

    // ── Deleting ────────────────────────────────────────────────────────────

    func requestDelete(_ ids: [Int]) { if !ids.isEmpty { pendingDelete = ids } }
    func requestDeleteSelection() { requestDelete(Array(rows.selected)) }

    var deleteTitle: String {
        (pendingDelete?.count ?? 1) > 1 ? "Delete \(pendingDelete?.count ?? 0) tasks?" : "Delete this task?"
    }

    func confirmDelete(_ ids: [Int]) async {
        pendingDelete = nil
        if ids.count == 1, let id = ids.first {
            await store.delete(id)
        } else {
            store.selection = Set(ids)
            await store.deleteSelected()
        }
        syncSelection()
        syncOpen()
    }

    var canAct: Bool { !rows.isEmpty }
}

/// True while a text field has the cursor, so single keys and ⌘⌫ type or edit instead of acting on rows
enum MacFocus {
    @MainActor static var isEditingText: Bool { NSApp.keyWindow?.firstResponder is NSText }
}
