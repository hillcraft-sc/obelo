import AppKit
import SwiftUI

/// Everything the Reminders screen does, so the views only draw and call. The data and the rules are in
/// `RemindersStore` and `ReminderEditSession` (Shared, tested); this holds the screen's own state: the
/// row selection with its ⌘/⇧ rules, the "New reminder" form, and what waits for a confirmation.
@MainActor @Observable
final class RemindersScreenModel {
    let store: RemindersStore
    private(set) var session: ReminderEditSession?
    var rows = RowSelection<Int>()
    var bulkAction = "complete"
    /// Ids waiting for the "Delete this reminder?" confirmation
    var pendingDelete: [Int]?
    var focusTitle = false
    var timeZone: TimeZone = .current
    /// The "New reminder" form: set while it is open in the right pane
    var newDraft: ReminderDraft?
    var message: String?
    var messageIsError = false

    private var wantsTitleFocus = false

    init(store: RemindersStore = RemindersStore()) { self.store = store }

    // ── What's on screen ────────────────────────────────────────────────────

    var displayedIDs: [Int] { store.reminders.map(\.id) }

    var emptyMessage: String {
        if store.isFiltered { return "No reminders match this filter." }
        switch store.view {
        case "upcoming": return "No upcoming reminders yet."
        case "today": return "Nothing due today."
        case "overdue": return "Nothing overdue."
        case "completed": return "No completed reminders yet."
        default: return "No reminders yet."
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

    private func syncSelection() { rows.set(store.selection) }

    /// "Show this reminder" (a click on a reminder in Today): its tab, selected
    func show(reminder id: Int) async {
        await session?.flush(leaving: true)
        newDraft = nil
        if store.isFiltered { store.tag = nil }
        guard let r = await store.fetch(id) else { await load(); return }
        await store.show(view: RemindersStore.view(for: r))
        rows = RowSelection()
        rows.click(id, in: [id])
        await store.select([id])
        syncOpen()
    }

    // ── Selection and the open reminder ─────────────────────────────────────

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
            newDraft = nil
            await store.select(ids)
            syncOpen()
        }
    }

    /// Makes a new edit session when the open reminder changed (called when `store.open` changes)
    func syncOpen() {
        guard let open = store.open else { session = nil; return }
        if session?.reminderId != open.id {
            session = ReminderEditSession(reminder: open, store: store)
            if wantsTitleFocus {
                wantsTitleFocus = false
                Task { try? await Task.sleep(for: .milliseconds(80)); focusTitle = true }
            }
        }
    }

    /// Saves what's pending (leaving the screen, quitting)
    func leave() async { await session?.flush(leaving: true) }

    // ── New reminder ────────────────────────────────────────────────────────

    /// "New reminder": an empty form in the right pane with today, the next full hour and "At the due time"
    func newReminder() async {
        await session?.flush(leaving: true)
        rows.clear()
        await store.select([])
        syncOpen()
        newDraft = ReminderDraft.blank(in: timeZone)
        focusTitle = true
        await store.loadAllTags()
    }

    func cancelNew() { newDraft = nil }

    /// "Add reminder": creates it, shows the tab it lands in and selects it
    func addNew() async {
        guard let draft = newDraft else { return }
        guard let made = await store.create(draft) else { return }
        newDraft = nil
        await store.show(view: RemindersStore.view(for: made))
        rows = RowSelection()
        rows.click(made.id, in: [made.id])
        await store.select([made.id])
        syncOpen()
    }

    // ── Changing reminders ──────────────────────────────────────────────────

    func complete(_ id: Int) async {
        if session?.reminderId == id { await session?.flush() }
        await store.complete(id)
        afterChange()
    }

    func restore(_ id: Int) async {
        await store.restore(id)
        afterChange()
    }

    func snooze(_ id: Int, _ duration: String) async {
        if session?.reminderId == id { await session?.flush() }   // pending edits go first, so they aren't overwritten
        await store.snooze(id, duration)
        if store.open?.id == id || rows.selected == [id] {
            await store.openReminder(id)
            if let o = store.open { session?.adopt(o) }
        }
        syncSelection()
    }

    private func afterChange() { syncSelection(); syncOpen() }

    /// Mark complete (or restore) for the selection, from the menu, ⌘Return or the bar
    func completeSelection() async {
        let ids = Array(rows.selected)
        guard !ids.isEmpty else { return }
        if ids.count == 1, let id = ids.first {
            if store.reminders.first(where: { $0.id == id })?.completed == true { await restore(id) } else { await complete(id) }
        } else {
            await bulk("complete")
        }
    }

    func applyBulk() async { await bulk(bulkAction) }

    /// One request for the whole selection; says how many were changed
    func bulk(_ action: String) async {
        await session?.flush(leaving: true)
        store.selection = rows.selected
        let asked = rows.count
        let done = await store.applyBulk(action)
        if store.error == nil {
            let what = action == "delete" ? "deleted" : "marked complete"
            message = done == asked ? "\(done) reminder\(done == 1 ? "" : "s") \(what)"
                                    : "\(done) of \(asked) reminders \(what). The others were already done or gone."
            messageIsError = false
            rows.clear()
        } else {
            syncSelection()   // a failed request leaves the selection as it was
        }
        syncOpen()
    }

    // ── Deleting ────────────────────────────────────────────────────────────

    func requestDelete(_ ids: [Int]) { if !ids.isEmpty { pendingDelete = ids } }
    func requestDeleteSelection() { requestDelete(Array(rows.selected)) }

    var deleteTitle: String {
        (pendingDelete?.count ?? 1) > 1 ? "Delete \(pendingDelete?.count ?? 0) reminders?" : "Delete this reminder?"
    }

    func confirmDelete(_ ids: [Int]) async {
        pendingDelete = nil
        if ids.count == 1, let id = ids.first {
            await store.delete(id)
        } else {
            rows.set(Set(ids))
            await bulk("delete")
            return
        }
        syncSelection()
        syncOpen()
    }

    var canAct: Bool { !rows.isEmpty }
}
