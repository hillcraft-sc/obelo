import AppKit
import SwiftUI

/// Everything the Routines screen does, so the views only draw and call. The data and the rules are in
/// `RoutinesStore` and `RoutineEditSession` (Shared, tested); this holds the screen's own state: the row
/// selection with its ⌘/⇧ rules, the "New routine" form, and what waits for a confirmation.
@MainActor @Observable
final class RoutinesScreenModel {
    let store: RoutinesStore
    private(set) var session: RoutineEditSession?
    var rows = RowSelection<Int>()
    var bulkAction = "archive"
    /// Ids waiting for the "Delete this routine and all its history?" confirmation
    var pendingDelete: [Int]?
    var focusTitle = false
    /// The "New routine" form: set while it is open in the right pane
    var newDraft: RoutineDraft?
    var message: String?
    var messageIsError = false

    private var wantsTitleFocus = false

    init(store: RoutinesStore = RoutinesStore()) { self.store = store }

    // ── What's on screen ────────────────────────────────────────────────────

    var emptyMessage: String {
        if store.isFiltered { return "No routines match this filter." }
        switch store.view {
        case "archived": return "No archived routines yet."
        case "today" where !store.routines.isEmpty: return "Nothing due today."
        default: return "No routines yet."
        }
    }

    // ── Loading ─────────────────────────────────────────────────────────────

    func load() async { await store.load(); syncSelection() }

    func show(view: String) async {
        await session?.flush(leaving: true)
        await store.show(view: view)
        rows.clear()
        bulkAction = store.bulkChoices.first?.0 ?? "delete"
    }

    func toggleTag(_ tag: String) async { await store.toggleTag(tag); syncSelection() }
    func clearFilter() async { await store.clearFilter(); syncSelection() }

    private func syncSelection() { rows.set(store.selection) }

    /// "Show this routine" (a click on a routine in Today): its tab, selected
    func show(routine id: Int) async {
        await session?.flush(leaving: true)
        newDraft = nil
        if store.isFiltered { store.tag = nil }
        guard let r = await store.fetch(id) else { await load(); return }
        await store.show(view: RoutinesStore.view(for: r))
        bulkAction = store.bulkChoices.first?.0 ?? "delete"
        rows = RowSelection()
        rows.click(id, in: [id])
        await store.select([id])
        syncOpen()
    }

    // ── Selection and the open routine ──────────────────────────────────────

    func click(_ id: Int, command: Bool, shift: Bool) {
        rows.click(id, in: store.displayedIDs, command: command, shift: shift)
        choose(rows.selected)
    }

    /// The row's tick box: adds or removes it from the selection
    func tick(_ id: Int) {
        rows.click(id, in: store.displayedIDs, command: true)
        choose(rows.selected)
    }

    func arrow(_ delta: Int) {
        rows.step(delta, in: store.displayedIDs)
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

    /// Makes a new edit session when the open routine changed (called when `store.open` changes)
    func syncOpen() {
        guard let open = store.open?.routine else { session = nil; return }
        if session?.routineId != open.id {
            session = RoutineEditSession(routine: open, store: store)
            if wantsTitleFocus {
                wantsTitleFocus = false
                Task { try? await Task.sleep(for: .milliseconds(80)); focusTitle = true }
            }
        }
    }

    /// Saves what's pending (leaving the screen, quitting)
    func leave() async { await session?.flush(leaving: true) }

    // ── New routine ─────────────────────────────────────────────────────────

    /// "New routine": an empty form in the right pane (Anytime, Daily, Ongoing, no notification)
    func newRoutine() async {
        await session?.flush(leaving: true)
        rows.clear()
        await store.select([])
        syncOpen()
        newDraft = RoutineDraft()
        focusTitle = true
        await store.loadAllTags()
    }

    func cancelNew() { newDraft = nil }

    /// "Add routine": creates it, shows the tab it lands in and selects it
    func addNew() async {
        guard let draft = newDraft else { return }
        guard let made = await store.create(draft) else { return }
        newDraft = nil
        await store.show(view: RoutinesStore.view(for: made))
        rows = RowSelection()
        rows.click(made.id, in: [made.id])
        await store.select([made.id])
        syncOpen()
    }

    // ── Changing routines ───────────────────────────────────────────────────

    /// Marks done for today, or undoes it. A routine not scheduled today can't be marked, as on the web.
    func toggleToday(_ id: Int) async {
        guard let r = store.routines.first(where: { $0.id == id }), r.completedToday || r.dueToday else { return }
        if session?.routineId == id { await session?.flush() }
        await store.toggleToday(id)
        syncSelection()
        syncOpen()
    }

    func toggleArchived(_ id: Int) async {
        if session?.routineId == id { await session?.flush(leaving: true) }
        await store.toggleArchived(id)
        syncSelection()
        syncOpen()
    }

    /// ⌘↩ and Space: one routine toggles; several are marked done (the ones due today and not done yet)
    func completeSelection() async {
        let ids = Array(rows.selected)
        guard !ids.isEmpty else { return }
        if ids.count == 1, let id = ids.first { await toggleToday(id); return }
        var done = 0
        for id in ids {
            guard let r = store.routines.first(where: { $0.id == id }), r.dueToday, !r.completedToday else { continue }
            await store.toggleToday(id)
            done += 1
        }
        message = done == 0 ? "Nothing to mark: they are done already or not scheduled today."
                            : "\(done) routine\(done == 1 ? "" : "s") marked done for today"
        messageIsError = false
        syncSelection()
    }

    func applyBulk() async { await bulk(bulkAction) }

    /// One request for the whole selection; says how many were changed
    func bulk(_ action: String) async {
        await session?.flush(leaving: true)
        store.selection = rows.selected
        let asked = rows.count
        let done = await store.applyBulk(action)
        if store.error == nil {
            let what = ["archive": "archived", "restore": "restored", "delete": "deleted"][action] ?? "changed"
            message = done == asked ? "\(done) routine\(done == 1 ? "" : "s") \(what)"
                                    : "\(done) of \(asked) routines \(what). The others were already so, or gone."
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
        (pendingDelete?.count ?? 1) > 1 ? "Delete \(pendingDelete?.count ?? 0) routines and all their history?" : "Delete this routine and all its history?"
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
}
