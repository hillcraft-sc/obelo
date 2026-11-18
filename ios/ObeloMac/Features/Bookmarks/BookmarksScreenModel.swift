import AppKit
import SwiftUI

/// Everything the Bookmarks screen does, so the views only draw and call. The data and the rules are in
/// `BookmarksStore` (Shared, tested); this holds the screen's own state: which form the right pane shows,
/// the draft being typed, what waits for a confirmation, the Share box.
@MainActor @Observable
final class BookmarksScreenModel {
    enum Mode: Equatable { case none, new, edit(Int) }

    let store: BookmarksStore
    var mode: Mode = .none
    var draft = BookmarkDraft()
    var focusURL = false
    var focusFilter = false
    var pendingDelete: [Int]?
    var showShare = false
    var shareName = ""
    /// The Share box's line under the field: the server's words and whether they are a problem
    var shareReply: (text: String, isError: Bool)?
    var message: String?
    var messageIsError = false

    init(store: BookmarksStore = BookmarksStore()) { self.store = store }

    // ── Loading ─────────────────────────────────────────────────────────────

    func load() async {
        await store.load()
        if store.tagSuggestions.isEmpty { await store.loadTagSuggestions() }
        syncPane()
    }

    // ── Which form the right pane shows ─────────────────────────────────────

    /// One row selected: its form. Several or none: nothing, unless "New bookmark" is open.
    func syncPane() {
        if let id = store.selection.single, let b = store.bookmarks.first(where: { $0.id == id }) {
            if mode != .edit(id) { mode = .edit(id); draft = Self.draft(from: b); shareReply = nil }
        } else if mode != .new {
            mode = .none
        }
    }

    static func draft(from b: Bookmark) -> BookmarkDraft {
        BookmarkDraft(url: b.url, title: b.title ?? "", description: b.description ?? "", tags: b.tags)
    }

    var editing: Bookmark? {
        guard case .edit(let id) = mode else { return nil }
        return store.bookmarks.first { $0.id == id }
    }

    var isDirty: Bool {
        switch mode {
        case .new: return draft != BookmarkDraft()
        case .edit: return editing.map { Self.draft(from: $0) != draft } ?? false
        case .none: return false
        }
    }

    var canSave: Bool { !draft.url.trimmingCharacters(in: .whitespaces).isEmpty }

    func click(_ id: Int, command: Bool, shift: Bool) {
        store.click(id, command: command, shift: shift)
        syncPane()
    }

    func newBookmark() {
        store.clearSelection()
        mode = .new
        draft = BookmarkDraft()
        shareReply = nil
        focusURL = true
    }

    func edit() {
        if editing != nil { focusURL = true }
    }

    func save() async {
        switch mode {
        case .new:
            if let b = await store.add(draft) {
                store.clearSelection()
                mode = .none
                store.click(b.id)
                syncPane()
                message = "Bookmark added"; messageIsError = false
            }
        case .edit(let id):
            if await store.update(id, draft), let b = store.bookmarks.first(where: { $0.id == id }) {
                draft = Self.draft(from: b)
                message = "Bookmark saved"; messageIsError = false
            }
        case .none: break
        }
    }

    /// Cancel: a new form closes; an edited one goes back to what is saved
    func cancel() {
        switch mode {
        case .new: mode = .none
        case .edit: if let b = editing { draft = Self.draft(from: b) }
        case .none: break
        }
    }

    // ── Rows ────────────────────────────────────────────────────────────────

    /// Right-click on a row outside the selection acts on that row alone
    func ensureSelected(_ id: Int) {
        if !store.selection.contains(id) { click(id, command: false, shift: false) }
    }

    func open(_ b: Bookmark) {
        guard b.isWebLink, let url = URL(string: b.url) else { return }
        NSWorkspace.shared.open(url)
    }

    func openSelection() {
        if let b = store.selected { open(b) }
    }

    func copyLink(_ b: Bookmark) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(b.url, forType: .string)
        message = "Link copied"; messageIsError = false
    }

    // ── Delete ──────────────────────────────────────────────────────────────

    func requestDelete() {
        let ids = store.selectedBookmarks.map(\.id)
        if !ids.isEmpty { pendingDelete = ids }
    }

    func requestDelete(_ id: Int) {
        ensureSelected(id)
        requestDelete()
    }

    var deleteTitle: String { (pendingDelete?.count ?? 0) > 1 ? "Delete selected bookmarks?" : "Delete this bookmark?" }

    func confirmDelete(_ ids: [Int]) async {
        pendingDelete = nil
        if ids.count > 1 { await store.deleteSelected() } else if let id = ids.first { await store.delete(id) }
        syncPane()
    }

    // ── Share ───────────────────────────────────────────────────────────────

    func openShare(_ id: Int) {
        ensureSelected(id)
        shareName = ""; shareReply = nil
        showShare = true
        Task { await store.loadShareable() }
    }

    func sendToUser() async {
        guard let b = editing else { return }
        if let reply = await store.send(b.id, to: shareName) {
            shareReply = (reply, false); shareName = ""
        } else {
            shareReply = (store.error ?? "Something went wrong", true)
            store.error = nil
        }
    }

    /// Share via text message: Messages if this Mac has it, otherwise the text goes on the clipboard
    func shareAsText(_ b: Bookmark) {
        let text = BookmarksStore.textForMessage(b)
        if let service = NSSharingService(named: .composeMessage), service.canPerform(withItems: [text]) {
            service.perform(withItems: [text])
        } else {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            message = "Messages isn't available here. The text is on the clipboard."
            messageIsError = false
        }
    }
}
