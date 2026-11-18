import AppKit
import SwiftUI

/// Everything the Lists screen does, so the views only draw and call. The data and the rules are in
/// `ListsStore` (Shared, tested); this holds the screen's own state: the "New list" form, the title being
/// edited, the item being edited, the row selected for the keyboard, what waits for a confirmation.
@MainActor @Observable
final class ListsScreenModel {
    let store: ListsStore
    /// The "New list" form: the name typed so far, set while the form is open in the right pane
    var newName: String?
    var titleDraft = ""
    var itemText = ""
    var editingItem: Int?
    var editText = ""
    /// The open item the keyboard acts on (Space, Delete, ⌥↑ ⌥↓)
    var selectedItem: Int?
    var shareName = ""
    var pendingDeleteList: Int?
    var focusNewName = false
    var focusTitle = false
    var focusAddItem = false
    var message: String?
    var messageIsError = false

    init(store: ListsStore = ListsStore()) { self.store = store }

    // ── Loading and opening ─────────────────────────────────────────────────

    func load() async { await store.load(); syncTitle() }

    func select(_ id: Int) async {
        guard id != store.selectedID || newName != nil else { return }
        await commitTitle()
        resetPane()
        await store.select(id)
        syncTitle()
    }

    /// "Show this list" (a click on a list from another screen)
    func show(list id: Int) async {
        await load()
        await select(id)
    }

    func leave() async { await commitTitle() }

    private func resetPane() {
        newName = nil; itemText = ""; editingItem = nil; selectedItem = nil; shareName = ""
    }

    // ── New list ────────────────────────────────────────────────────────────

    func newList() async {
        await commitTitle()
        resetPane()
        await store.select(nil)
        newName = ""
        focusNewName = true
    }

    func cancelNew() { newName = nil }

    func createNew() async {
        guard let name = newName else { return }
        guard let made = await store.create(title: name) else { return }
        newName = nil
        syncTitle()
        focusAddItem = true
        _ = made
    }

    // ── Rename ──────────────────────────────────────────────────────────────

    func syncTitle() { titleDraft = store.open?.title ?? "" }

    /// Return or leaving the pane: saves a changed title. An empty title puts the old one back.
    func commitTitle() async {
        guard let o = store.open, o.isOwner else { return }
        let t = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty || t == o.title { syncTitle(); return }
        if await !store.rename(o.id, to: t) { syncTitle() }
        syncTitle()
    }

    func revertTitle() { syncTitle() }

    // ── Items ───────────────────────────────────────────────────────────────

    func addItem() async {
        if await store.addItem(itemText) { itemText = ""; focusAddItem = true }
    }

    func toggle(_ id: Int) async { await store.toggle(id) }

    func startEdit(_ id: Int) {
        guard let item = store.open?.items.first(where: { $0.id == id }) else { return }
        editingItem = id; editText = item.text; selectedItem = id
    }

    func saveEdit() async {
        guard let id = editingItem else { return }
        if await store.editItem(id, text: editText) || editText.trimmingCharacters(in: .whitespaces).isEmpty { editingItem = nil }
    }

    func cancelEdit() { editingItem = nil }

    func deleteItem(_ id: Int) async {
        let ids = store.activeItems.map(\.id)
        await store.deleteItem(id)
        if selectedItem == id { selectedItem = nil }
        _ = ids
    }

    /// A row dropped on another: the dragged row takes the place of the one it lands on
    func drop(_ dragged: Int, onto target: Int) -> Bool {
        let active = store.activeItems.map(\.id)
        guard let from = active.firstIndex(of: dragged), let to = active.firstIndex(of: target), from != to else { return false }
        Task { await store.moveActive(from: from, to: to > from ? to + 1 : to) }
        return true
    }

    func nudge(_ id: Int, by step: Int) { Task { await store.nudge(id, by: step) } }

    /// Up and down arrows move the keyboard row through the open items, then the done ones
    func arrow(_ delta: Int) {
        let ids = (store.activeItems + store.doneItems).map(\.id)
        guard !ids.isEmpty else { return }
        guard let cur = selectedItem, let i = ids.firstIndex(of: cur) else { selectedItem = delta > 0 ? ids.first : ids.last; return }
        selectedItem = ids[min(max(i + delta, 0), ids.count - 1)]
    }

    // ── Sharing ─────────────────────────────────────────────────────────────

    func share() async {
        if await store.share(username: shareName) { shareName = "" }
    }

    /// Send as text message: Messages if this Mac has it, otherwise the text goes on the clipboard
    func sendAsText() {
        guard let text = store.textForMessage else { return }
        if let service = NSSharingService(named: .composeMessage), service.canPerform(withItems: [text]) {
            service.perform(withItems: [text])
        } else {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            message = "Messages isn't available here. The list is on the clipboard."
            messageIsError = false
        }
    }

    // ── Deleting a list ─────────────────────────────────────────────────────

    func requestDeleteOpenList() {
        if let o = store.open, o.isOwner { pendingDeleteList = o.id }
    }

    func confirmDelete(_ id: Int) async {
        pendingDeleteList = nil
        await store.delete(id)
        resetPane(); syncTitle()
    }
}
