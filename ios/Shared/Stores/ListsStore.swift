import SwiftUI

// The Lists module's logic, with no interface: your lists and the ones shared with you, the open list
// with its items (open first, done below), add / tick / edit / delete / reorder, rename, delete list,
// sharing with name suggestions. The Mac screen is built on it. It talks to the server through
// `ListsAPI`, so tests can use a stub.

struct ListsResponse: Decodable, Equatable {
    let lists: [ListSummary]
    let shared: [ListSummary]
}

@MainActor
protocol ListsAPI {
    func lists() async throws -> ListsResponse
    func detail(id: Int) async throws -> ListDetail
    func create(title: String) async throws -> ListSummary
    func rename(id: Int, title: String) async throws
    func delete(id: Int) async throws
    func addItem(listID: Int, text: String) async throws -> ListEntry
    /// Toggles the item and returns whether it is now checked
    func toggle(listID: Int, itemID: Int) async throws -> Bool
    func editItem(listID: Int, itemID: Int, text: String) async throws
    func deleteItem(listID: Int, itemID: Int) async throws
    /// The ids of the open items, in their new order
    func reorder(listID: Int, ids: [Int]) async throws
    func share(listID: Int, username: String) async throws
    func unshare(listID: Int, userID: Int) async throws
    func shareable() async throws -> [ListDetail.SharedUser]
}

@MainActor
struct LiveListsAPI: ListsAPI {
    private var api: APIClient { .shared }
    private struct One: Decodable { let list: ListSummary }
    private struct Detail: Decodable { let list: ListDetail }
    private struct Item: Decodable { let item: ListEntry }
    private struct Checked: Decodable { let checked: Bool }
    private struct Users: Decodable { let users: [ListDetail.SharedUser] }

    func lists() async throws -> ListsResponse { try await api.get("/lists") }
    func detail(id: Int) async throws -> ListDetail { (try await api.get("/lists/\(id)") as Detail).list }
    func create(title: String) async throws -> ListSummary { (try await api.post("/lists", ["title": title]) as One).list }
    func rename(id: Int, title: String) async throws { try await api.post("/lists/\(id)", ["title": title], method: "PATCH") }
    func delete(id: Int) async throws { try await api.delete("/lists/\(id)") }
    func addItem(listID: Int, text: String) async throws -> ListEntry {
        (try await api.post("/lists/\(listID)/items", ["text": text]) as Item).item
    }
    func toggle(listID: Int, itemID: Int) async throws -> Bool {
        (try await api.post("/lists/\(listID)/items/\(itemID)/toggle") as Checked).checked
    }
    func editItem(listID: Int, itemID: Int, text: String) async throws {
        try await api.post("/lists/\(listID)/items/\(itemID)", ["text": text], method: "PATCH")
    }
    func deleteItem(listID: Int, itemID: Int) async throws { try await api.delete("/lists/\(listID)/items/\(itemID)") }
    func reorder(listID: Int, ids: [Int]) async throws { try await api.post("/lists/\(listID)/items/reorder", ["ids": ids]) }
    func share(listID: Int, username: String) async throws { try await api.post("/lists/\(listID)/share", ["username": username]) }
    func unshare(listID: Int, userID: Int) async throws { try await api.delete("/lists/\(listID)/share/\(userID)") }
    func shareable() async throws -> [ListDetail.SharedUser] { (try await api.get("/users/shareable") as Users).users }
}

@MainActor @Observable
final class ListsStore {
    private let api: ListsAPI

    private(set) var mine: [ListSummary] = []
    private(set) var shared: [ListSummary] = []
    private(set) var loaded = false
    var error: String?

    /// The list in the right pane
    private(set) var selectedID: Int?
    private(set) var open: ListDetail?
    /// Everyone you could share with, for the suggestions
    private(set) var shareable: [ListDetail.SharedUser] = []

    init(api: ListsAPI) { self.api = api }
    convenience init() { self.init(api: LiveListsAPI()) }

    // ── What's on screen ────────────────────────────────────────────────────

    var isEmpty: Bool { mine.isEmpty && shared.isEmpty }
    /// "My Lists" is only headed when something is also shared with you (as the web)
    var showsMineHeading: Bool { !shared.isEmpty }
    var displayedIDs: [Int] { (mine + shared).map(\.id) }

    var activeItems: [ListEntry] { (open?.items ?? []).filter { !$0.checked }.sorted { $0.position < $1.position } }
    var doneItems: [ListEntry] { (open?.items ?? []).filter(\.checked).sorted { $0.position < $1.position } }

    /// "3 active · 2 done" for a row
    static func counts(_ l: ListSummary) -> String {
        let done = l.itemCount - l.openCount
        return "\(l.openCount) active" + (done > 0 ? " · \(done) done" : "")
    }

    /// The list as text for Messages: title, "• open", "✓ done"
    var textForMessage: String? {
        guard let o = open else { return nil }
        var lines = [o.title, ""]
        if o.items.isEmpty { lines.append("(no items)") }
        activeItems.forEach { lines.append("• " + $0.text) }
        doneItems.forEach { lines.append("✓ " + $0.text) }
        return lines.joined(separator: "\n")
    }

    // ── Lists ───────────────────────────────────────────────────────────────

    func load() async {
        do {
            let r = try await api.lists()
            mine = r.lists; shared = r.shared; loaded = true; error = nil
            if let id = selectedID, !displayedIDs.contains(id) { selectedID = nil; open = nil }
        } catch { self.error = error.localizedDescription }
    }

    func select(_ id: Int?) async {
        selectedID = id
        guard let id else { open = nil; return }
        await openList(id)
    }

    func openList(_ id: Int) async {
        do {
            let d = try await api.detail(id: id)
            guard selectedID == id else { return }   // the person moved on while it loaded
            open = d; error = nil
        } catch { self.error = error.localizedDescription }
    }

    /// Creates a list and opens it. An empty name is refused.
    @discardableResult
    func create(title: String) async -> ListSummary? {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { error = "Title is required."; return nil }
        do {
            let l = try await api.create(title: t)
            mine.insert(l, at: 0); error = nil
            await select(l.id)
            return l
        } catch { self.error = error.localizedDescription; return nil }
    }

    /// Owner only. The title changes in the list and in the open pane.
    @discardableResult
    func rename(_ id: Int, to title: String) async -> Bool {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return false }
        do {
            try await api.rename(id: id, title: t)
            if let i = mine.firstIndex(where: { $0.id == id }) { mine[i] = mine[i].with(title: t) }
            if open?.id == id { open = open?.with(title: t) }
            error = nil
            return true
        } catch { self.error = error.localizedDescription; return false }
    }

    func delete(_ id: Int) async {
        do {
            try await api.delete(id: id)
            mine.removeAll { $0.id == id }
            if selectedID == id { selectedID = nil; open = nil }
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    // ── Items (the open list) ───────────────────────────────────────────────

    /// Adds an item at the end of the open ones. Empty text is ignored.
    @discardableResult
    func addItem(_ text: String) async -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let id = selectedID, !t.isEmpty else { return false }
        do {
            let item = try await api.addItem(listID: id, text: t)
            guard open?.id == id else { return true }
            open?.items.append(item)
            adjustCounts(id, total: 1, open: 1)
            error = nil
            return true
        } catch { self.error = error.localizedDescription; return false }
    }

    /// Ticks or unticks at once; put back if the server refuses
    func toggle(_ itemID: Int) async {
        guard let id = selectedID, let i = open?.items.firstIndex(where: { $0.id == itemID }) else { return }
        let was = open!.items[i].checked
        setChecked(itemID, !was, in: id)
        do {
            let now = try await api.toggle(listID: id, itemID: itemID)
            if now != !was { setChecked(itemID, now, in: id) }
            error = nil
        } catch {
            setChecked(itemID, was, in: id)
            self.error = error.localizedDescription
        }
    }

    @discardableResult
    func editItem(_ itemID: Int, text: String) async -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let id = selectedID, !t.isEmpty, let i = open?.items.firstIndex(where: { $0.id == itemID }) else { return false }
        let old = open!.items[i].text
        open?.items[i].text = t
        do { try await api.editItem(listID: id, itemID: itemID, text: t); error = nil; return true }
        catch {
            if let j = open?.items.firstIndex(where: { $0.id == itemID }) { open?.items[j].text = old }
            self.error = error.localizedDescription
            return false
        }
    }

    func deleteItem(_ itemID: Int) async {
        guard let id = selectedID, let item = open?.items.first(where: { $0.id == itemID }) else { return }
        do {
            try await api.deleteItem(listID: id, itemID: itemID)
            open?.items.removeAll { $0.id == itemID }
            adjustCounts(id, total: -1, open: item.checked ? 0 : -1)
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    /// Moves an open item to a new place among the open ones (`to` counts positions in the open items,
    /// before the move is taken out, like SwiftUI's `move`). Sent as one request; put back if it fails.
    func moveActive(from: Int, to: Int) async {
        guard let id = selectedID, var items = open?.items else { return }
        var active = activeItems
        guard active.indices.contains(from), to >= 0, to <= active.count else { return }
        let before = items
        let moved = active.remove(at: from)
        active.insert(moved, at: to > from ? to - 1 : to)
        guard active.map(\.id) != activeItems.map(\.id) else { return }
        let done = doneItems
        items = (active + done).enumerated().map { var e = $0.element; e.position = $0.offset; return e }
        open?.items = items
        do { try await api.reorder(listID: id, ids: active.map(\.id)); error = nil }
        catch { open?.items = before; self.error = error.localizedDescription }
    }

    /// Moves the open item one place up (-1) or down (+1), for ⌥↑ ⌥↓
    func nudge(_ itemID: Int, by step: Int) async {
        guard let from = activeItems.firstIndex(where: { $0.id == itemID }) else { return }
        let target = from + step
        guard target >= 0, target < activeItems.count else { return }
        await moveActive(from: from, to: step > 0 ? target + 1 : target)
    }

    // ── Sharing (owner only) ────────────────────────────────────────────────

    /// Loads the people you could share with. If the server can't say (an older server without the call, or
    /// no connection), `error` says so, and the next call tries again.
    func loadShareable() async {
        guard shareable.isEmpty else { return }
        do { shareable = try await api.shareable() }
        catch { self.error = "Couldn't load the people you can share with. \(error.localizedDescription)" }
    }

    /// People you can pick, not already on the list: everyone when nothing is typed (as the web's list), then
    /// the ones matching what has been typed (name or username)
    func suggestions(for typed: String) -> [ListDetail.SharedUser] {
        let q = typed.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "@")).lowercased()
        let already = Set((open?.sharedWith ?? []).map(\.id))
        return shareable.filter { u in
            !already.contains(u.id) && (q.isEmpty || u.username.lowercased().hasPrefix(q) || u.displayName.lowercased().contains(q))
        }
    }

    /// Shares the open list with a username. Returns false (and sets `error` to the server's words) when it can't.
    @discardableResult
    func share(username: String) async -> Bool {
        let u = username.trimmingCharacters(in: .whitespaces)
        guard let id = selectedID, !u.isEmpty else { return false }
        do {
            try await api.share(listID: id, username: u)
            error = nil
            await openList(id)
            return true
        } catch { self.error = error.localizedDescription; return false }
    }

    func unshare(_ userID: Int) async {
        guard let id = selectedID else { return }
        do {
            try await api.unshare(listID: id, userID: userID)
            open = open?.with(sharedWith: (open?.sharedWith ?? []).filter { $0.id != userID })
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    // ── Internals ───────────────────────────────────────────────────────────

    private func setChecked(_ itemID: Int, _ checked: Bool, in listID: Int) {
        guard let i = open?.items.firstIndex(where: { $0.id == itemID }), open?.items[i].checked != checked else { return }
        open?.items[i].checked = checked
        adjustCounts(listID, total: 0, open: checked ? -1 : 1)
    }

    private func adjustCounts(_ listID: Int, total: Int, open: Int) {
        func bump(_ l: ListSummary) -> ListSummary { l.with(itemCount: l.itemCount + total, openCount: l.openCount + open) }
        if let i = mine.firstIndex(where: { $0.id == listID }) { mine[i] = bump(mine[i]) }
        else if let i = shared.firstIndex(where: { $0.id == listID }) { shared[i] = bump(shared[i]) }
    }
}

private extension ListSummary {
    func with(title: String? = nil, itemCount: Int? = nil, openCount: Int? = nil) -> ListSummary {
        ListSummary(id: id, title: title ?? self.title, createdAt: createdAt, isOwner: isOwner, owner: owner,
                    itemCount: itemCount ?? self.itemCount, openCount: openCount ?? self.openCount)
    }
}

private extension ListDetail {
    func with(title: String? = nil, sharedWith: [SharedUser]? = nil) -> ListDetail {
        ListDetail(id: id, title: title ?? self.title, isOwner: isOwner, owner: owner, items: items,
                   sharedWith: sharedWith ?? self.sharedWith)
    }
}
