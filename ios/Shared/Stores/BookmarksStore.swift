import Foundation
import SwiftUI

// The Bookmarks module's logic, with no interface: all your bookmarks, the tag filter and the search
// (done here, over what was loaded, as the web does), sorting for the table, row selection, add / edit /
// delete / delete several, and sending one to another Obelo user. The Mac screen is built on it. It
// talks to the server through `BookmarksAPI`, so tests can use a stub.

struct BookmarksResponse: Decodable, Equatable {
    let bookmarks: [Bookmark]
    let tags: [String]
}

struct BookmarkDraft: Equatable {
    var url = ""
    var title = ""
    var description = ""
    var tags: [String] = []
}

@MainActor
protocol BookmarksAPI {
    func list() async throws -> BookmarksResponse
    /// Every tag you use anywhere (the picker's suggestions)
    func allTags() async throws -> [String]
    func create(_ draft: BookmarkDraft) async throws -> Bookmark
    func update(id: Int, _ draft: BookmarkDraft) async throws
    func delete(id: Int) async throws
    /// Deletes several at once and says how many were deleted
    func deleteMany(ids: [Int]) async throws -> Int
    /// Sends a copy to another user; returns the server's words ("Sent to @sam")
    func send(id: Int, username: String) async throws -> String
    func shareable() async throws -> [ListDetail.SharedUser]
}

@MainActor
struct LiveBookmarksAPI: BookmarksAPI {
    private var api: APIClient { .shared }
    private struct One: Decodable { let bookmark: Bookmark }
    private struct Tags: Decodable { let tags: [String] }
    private struct Count: Decodable { let count: Int }
    private struct Message: Decodable { let message: String }
    private struct Users: Decodable { let users: [ListDetail.SharedUser] }

    private func body(_ d: BookmarkDraft) -> [String: Any] {
        ["url": d.url, "title": d.title, "description": d.description, "tags": d.tags]
    }

    func list() async throws -> BookmarksResponse { try await api.get("/bookmarks") }
    func allTags() async throws -> [String] { (try await api.get("/tags") as Tags).tags }
    func create(_ draft: BookmarkDraft) async throws -> Bookmark { (try await api.post("/bookmarks", body(draft)) as One).bookmark }
    func update(id: Int, _ draft: BookmarkDraft) async throws { try await api.post("/bookmarks/\(id)", body(draft), method: "PUT") }
    func delete(id: Int) async throws { try await api.delete("/bookmarks/\(id)") }
    func deleteMany(ids: [Int]) async throws -> Int { (try await api.post("/bookmarks/bulk-delete", ["ids": ids]) as Count).count }
    func send(id: Int, username: String) async throws -> String {
        (try await api.post("/bookmarks/\(id)/share-to-user", ["username": username]) as Message).message
    }
    func shareable() async throws -> [ListDetail.SharedUser] { (try await api.get("/users/shareable") as Users).users }
}

enum BookmarkSortKey: String, CaseIterable {
    case title, site, tags, added
}

extension Bookmark {
    /// The site without "www.", as the web shows it
    var site: String {
        let h = host
        return h.hasPrefix("www.") ? String(h.dropFirst(4)) : h
    }

    /// Only http and https addresses are opened or linked, as the web does
    var isWebLink: Bool {
        guard let u = URL(string: url), let s = u.scheme?.lowercased() else { return false }
        return s == "http" || s == "https"
    }

    /// What the web's filter box searches: title, address, note and tags
    fileprivate var searchText: String {
        [displayTitle, url, description ?? "", tags.joined(separator: " ")].joined(separator: " ").lowercased()
    }
}

@MainActor @Observable
final class BookmarksStore {
    private let api: BookmarksAPI

    private(set) var bookmarks: [Bookmark] = []
    private(set) var loaded = false
    /// Every tag on any bookmark, for the filter row
    private(set) var tagList: [String] = []
    /// Every tag you use anywhere, for the picker
    private(set) var tagSuggestions: [String] = []
    private(set) var shareable: [ListDetail.SharedUser] = []
    var error: String?

    var search = "" { didSet { pruneSelection() } }
    var activeTag: String? { didSet { pruneSelection() } }
    private(set) var sortKey: BookmarkSortKey = .added
    private(set) var ascending = false
    private(set) var selection = RowSelection<Int>()

    init(api: BookmarksAPI) { self.api = api }
    convenience init() { self.init(api: LiveBookmarksAPI()) }

    // ── What's on screen ────────────────────────────────────────────────────

    /// The rows shown: filtered by tag and search, then sorted. Newest first until a heading is clicked.
    var visible: [Bookmark] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        let filtered = bookmarks.filter { b in
            (activeTag == nil || b.tags.contains(activeTag!)) && (q.isEmpty || b.searchText.contains(q))
        }
        return filtered.sorted { a, b in
            let order = compare(a, b)
            if order == .orderedSame { return a.id > b.id }
            return ascending ? order == .orderedAscending : order == .orderedDescending
        }
    }

    var visibleIDs: [Int] { visible.map(\.id) }
    var isEmpty: Bool { bookmarks.isEmpty }
    /// Something is filtering the list (the empty state then says "No bookmarks match this filter.")
    var isFiltered: Bool { activeTag != nil || !search.trimmingCharacters(in: .whitespaces).isEmpty }

    private func compare(_ a: Bookmark, _ b: Bookmark) -> ComparisonResult {
        switch sortKey {
        case .title: return a.displayTitle.localizedCaseInsensitiveCompare(b.displayTitle)
        case .site: return a.site.localizedCaseInsensitiveCompare(b.site)
        case .tags: return a.tags.joined(separator: " ").localizedCaseInsensitiveCompare(b.tags.joined(separator: " "))
        case .added: return a.createdAt == b.createdAt ? .orderedSame : (a.createdAt < b.createdAt ? .orderedAscending : .orderedDescending)
        }
    }

    /// A click on a column heading: sorts by it, A to Z (newest first for Added); the same heading again reverses
    func sort(by key: BookmarkSortKey) {
        if sortKey == key { ascending.toggle() } else { sortKey = key; ascending = key != .added }
    }

    func clearFilter() { activeTag = nil; search = "" }

    /// Click on the tag in the filter row or on a row: filters by it; the active one clears
    func toggleTag(_ tag: String) { activeTag = activeTag == tag ? nil : tag }

    // ── Selection ───────────────────────────────────────────────────────────

    func click(_ id: Int, command: Bool = false, shift: Bool = false) { selection.click(id, in: visibleIDs, command: command, shift: shift) }
    func arrow(_ delta: Int) { selection.step(delta, in: visibleIDs) }
    func selectAll() { selection.selectAll(in: visibleIDs) }
    func clearSelection() { selection.clear() }
    var selectedBookmarks: [Bookmark] { visible.filter { selection.contains($0.id) } }
    var selected: Bookmark? { selection.single.flatMap { id in bookmarks.first { $0.id == id } } }

    private func pruneSelection() { selection.prune(to: visibleIDs) }

    // ── Loading ─────────────────────────────────────────────────────────────

    func load() async {
        do {
            let r = try await api.list()
            bookmarks = r.bookmarks
            tagList = Array(Set(r.bookmarks.flatMap(\.tags))).sorted()
            if let t = activeTag, !tagList.contains(t) { activeTag = nil }
            loaded = true; error = nil
            pruneSelection()
        } catch { self.error = error.localizedDescription }
    }

    /// The picker's suggestions: every tag you use anywhere, falling back to the ones on bookmarks
    func loadTagSuggestions() async {
        if let all = try? await api.allTags() { tagSuggestions = all } else { tagSuggestions = tagList }
    }

    // ── Add, edit, delete ───────────────────────────────────────────────────

    /// Adds a bookmark at the top. An empty address is refused with the server's words.
    @discardableResult
    func add(_ draft: BookmarkDraft) async -> Bookmark? {
        guard !draft.url.trimmingCharacters(in: .whitespaces).isEmpty else { error = "URL is required."; return nil }
        do {
            let b = try await api.create(draft)
            bookmarks.insert(b, at: 0)
            refreshTags()
            error = nil
            return b
        } catch { self.error = error.localizedDescription; return nil }
    }

    /// Saves changes. The list is loaded again afterwards so the address and tags are as the server kept them.
    @discardableResult
    func update(_ id: Int, _ draft: BookmarkDraft) async -> Bool {
        guard !draft.url.trimmingCharacters(in: .whitespaces).isEmpty else { error = "URL is required."; return false }
        do {
            try await api.update(id: id, draft)
            error = nil
            await load()
            return true
        } catch { self.error = error.localizedDescription; return false }
    }

    func delete(_ id: Int) async {
        do {
            try await api.delete(id: id)
            bookmarks.removeAll { $0.id == id }
            refreshTags(); pruneSelection()
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    /// Deletes every selected row in one request. Says how many went.
    @discardableResult
    func deleteSelected() async -> Int {
        let ids = selectedBookmarks.map(\.id)
        guard !ids.isEmpty else { return 0 }
        do {
            let n = try await api.deleteMany(ids: ids)
            bookmarks.removeAll { ids.contains($0.id) }
            refreshTags(); selection.clear()
            error = nil
            return n
        } catch { self.error = error.localizedDescription; return 0 }
    }

    private func refreshTags() {
        tagList = Array(Set(bookmarks.flatMap(\.tags))).sorted()
        if let t = activeTag, !tagList.contains(t) { activeTag = nil }
    }

    // ── Sharing ─────────────────────────────────────────────────────────────

    /// Loads the people you could send to. If the server can't say, `error` says so and the next call tries again.
    func loadShareable() async {
        guard shareable.isEmpty else { return }
        do { shareable = try await api.shareable() }
        catch { self.error = "Couldn't load the people you can send to. \(error.localizedDescription)" }
    }

    /// Everyone when nothing is typed (as the web's list), then the ones matching name or username
    func suggestions(for typed: String) -> [ListDetail.SharedUser] {
        let q = typed.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "@")).lowercased()
        return shareable.filter { q.isEmpty || $0.username.lowercased().hasPrefix(q) || $0.displayName.lowercased().contains(q) }
    }

    /// Sends a copy to a username. Returns the server's message, or nil with `error` set to its words
    /// ("No user found with username …", "Cannot share with yourself", "@sam already has this bookmark").
    func send(_ id: Int, to username: String) async -> String? {
        let u = username.trimmingCharacters(in: .whitespaces)
        guard !u.isEmpty else { error = "Username is required"; return nil }
        do { let m = try await api.send(id: id, username: u); error = nil; return m }
        catch { self.error = error.localizedDescription; return nil }
    }

    /// The text for "Share via text message": the title and the address, as the web
    static func textForMessage(_ b: Bookmark) -> String {
        b.displayTitle == b.url ? b.url : b.displayTitle + "\n" + b.url
    }
}
