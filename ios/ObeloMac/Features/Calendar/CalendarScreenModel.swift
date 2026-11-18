import AppKit
import SwiftUI

/// Everything the Calendar screen does, so the views only draw and call. The data and the rules are in
/// `CalendarStore` (Shared, tested); this holds the screen's own state: which pane is open on the right (the
/// event, the new-event form, the edit form), the draft being typed, what waits for a confirmation.
@MainActor @Observable
final class CalendarScreenModel {
    enum Pane: Equatable { case none, new, edit(Int) }

    let store: CalendarStore
    var pane: Pane = .none
    var draft = EventDraft()
    var focusTitle = false
    var pendingDelete: Int?
    var message: String?
    var messageIsError = false
    /// The red box above the form (the checks and the server's words)
    var formError: String?

    init(store: CalendarStore = CalendarStore()) { self.store = store }

    // ── The pane on the right ───────────────────────────────────────────────

    /// The right pane is open for an event, a new event or an edit
    var isPaneOpen: Bool { pane != .none || store.selected != nil }

    var isNew: Bool { pane == .new }
    var editing: CalendarEvent? {
        guard case .edit(let id) = pane else { return nil }
        return store.events.first { $0.id == id }
    }
    /// The event shown read-only: selected and not being edited
    var viewing: CalendarEvent? { pane == .none ? store.selected : nil }

    var isDirty: Bool {
        switch pane {
        case .new: return draft != EventDraft(date: draft.date, calendarTarget: draft.calendarTarget)
        case .edit: return editing.map { EventDraft($0) != draft } ?? false
        case .none: return false
        }
    }

    // ── Loading ─────────────────────────────────────────────────────────────

    func load() async { await store.load() }

    // ── Events ──────────────────────────────────────────────────────────────

    func select(_ id: Int) {
        pane = .none
        formError = nil
        store.select(id)
    }

    func close() {
        pane = .none
        formError = nil
        store.select(nil)
    }

    /// New event, on a day (a click on a day's number, a double-click on a day) or on the day shown
    func newEvent(on day: String? = nil) {
        store.select(nil)
        pane = .new
        draft = EventDraft(date: day ?? defaultDay, calendarTarget: store.defaultTarget)
        formError = nil
        focusTitle = true
        Task {
            await store.loadChoices()
            if pane == .new, !store.choices.contains(where: { $0.value == draft.calendarTarget }) { draft.calendarTarget = store.defaultTarget }
        }
    }

    /// Today if it is shown, otherwise the first day shown
    private var defaultDay: String {
        let today = store.today
        return today >= store.rangeStart && today <= store.rangeEnd ? today : store.rangeStart
    }

    func edit(_ id: Int) {
        guard let e = store.events.first(where: { $0.id == id }), e.editable else { return }
        store.select(id)
        pane = .edit(id)
        draft = EventDraft(e)
        formError = nil
        focusTitle = true
    }

    func editSelected() {
        if let id = store.selectedID { edit(id) }
    }

    func save() async {
        if let p = CalendarStore.problem(with: draft) { formError = p; return }
        switch pane {
        case .new:
            if await store.add(draft) != nil {
                pane = .none; formError = nil
                message = "Event created"; messageIsError = false
            } else { formError = store.error; store.error = nil }
        case .edit(let id):
            if await store.update(id, draft) {
                pane = .none; formError = nil
                message = "Event saved"; messageIsError = false
            } else { formError = store.error; store.error = nil }
        case .none: break
        }
    }

    /// Cancel: a new form closes; an edit goes back to showing the event
    func cancel() {
        switch pane {
        case .new: close()
        case .edit: pane = .none; formError = nil
        case .none: close()
        }
    }

    func open(_ e: CalendarEvent) {
        guard CalendarStore.isWebLink(e.url), let url = URL(string: e.url ?? "") else { return }
        NSWorkspace.shared.open(url)
    }

    // ── Delete ──────────────────────────────────────────────────────────────

    func requestDelete(_ id: Int) {
        if let e = store.events.first(where: { $0.id == id }), e.editable { pendingDelete = id }
    }

    func requestDeleteSelected() {
        if let id = store.selectedID { requestDelete(id) }
    }

    func confirmDelete(_ id: Int) async {
        pendingDelete = nil
        await store.delete(id)
        if store.selectedID == nil { pane = .none }
    }

    // ── Moving ──────────────────────────────────────────────────────────────

    func previous() { Task { await store.previous() } }
    func next() { Task { await store.next() } }
    func today() { Task { await store.goToToday() } }
    func setMode(_ m: CalendarViewMode) { Task { await store.setMode(m) } }
}
