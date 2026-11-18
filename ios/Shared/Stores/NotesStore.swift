import SwiftUI

// The Notes workspace's list logic, with no interface: the notes and folders, the tree in the order the
// web shows it, the pinned section, search, collapsing folders, and making, moving, pinning and
// deleting. Opening and editing one note is `NoteEditor`. The Mac screen is built on both. It talks to
// the server through `NotesAPI`, so tests can use a stub.

/// One row of the folder tree. `ancestors` are the folders above it (outermost first), so a collapsed
/// folder hides everything below it.
enum NoteTreeRow: Identifiable, Equatable {
    case folder(NoteFolder, depth: Int, ancestors: [Int])
    case note(NoteSummary, depth: Int, ancestors: [Int])

    var id: String {
        switch self {
        case .folder(let f, _, _): "f\(f.id)"
        case .note(let n, _, _): "n\(n.id)"
        }
    }

    var ancestors: [Int] {
        switch self {
        case .folder(_, _, let a), .note(_, _, let a): a
        }
    }
}

@MainActor
protocol NotesAPI {
    func list(search: String?) async throws -> [NoteSummary]
    func folders() async throws -> [NoteFolder]
    func createNote(_ body: [String: Any]) async throws -> Int
    func createFolder(name: String, parentId: Int?) async throws
    func renameFolder(id: Int, name: String) async throws
    func deleteFolder(id: Int) async throws
    func move(note: Int, to folder: Int?) async throws
    func togglePin(id: Int) async throws
    func deleteNote(id: Int) async throws
}

@MainActor
struct LiveNotesAPI: NotesAPI {
    private var api: APIClient { .shared }
    private struct Many: Decodable { let notes: [NoteSummary] }
    private struct Created: Decodable { struct N: Decodable { let id: Int }; let note: N }

    func list(search: String?) async throws -> [NoteSummary] {
        (try await api.get("/notes", query: ["search": (search?.isEmpty ?? true) ? nil : search]) as Many).notes
    }
    func folders() async throws -> [NoteFolder] { try await NoteFolders.load() }
    func createNote(_ body: [String: Any]) async throws -> Int { (try await api.post("/notes", body) as Created).note.id }
    func createFolder(name: String, parentId: Int?) async throws {
        let _: NoteFolders.One = try await api.post("/folders", ["name": name, "parentId": parentId.map { $0 as Any } ?? NSNull()])
    }
    func renameFolder(id: Int, name: String) async throws {
        let _: NoteFolders.One = try await api.post("/folders/\(id)", ["name": name], method: "PATCH")
    }
    func deleteFolder(id: Int) async throws { try await api.delete("/folders/\(id)") }
    func move(note: Int, to folder: Int?) async throws { try await NoteFolders.move(note: note, to: folder) }
    func togglePin(id: Int) async throws { try await api.post("/notes/\(id)/pin") }
    func deleteNote(id: Int) async throws { try await api.delete("/notes/\(id)") }
}

@MainActor @Observable
final class NotesStore {
    private let api: NotesAPI

    var search = ""
    private(set) var notes: [NoteSummary] = []
    private(set) var folders: [NoteFolder] = []
    private(set) var loaded = false
    var error: String?
    /// Folders folded shut (the screen remembers this between launches)
    var collapsed: Set<Int> = []

    init(api: NotesAPI) { self.api = api }
    convenience init() { self.init(api: LiveNotesAPI()) }

    var isFiltered: Bool { !search.trimmingCharacters(in: .whitespaces).isEmpty }

    /// Pinned notes, shown above the tree
    var pinned: [NoteSummary] { notes.filter(\.pinned) }

    // ── The tree ────────────────────────────────────────────────────────────

    /// Every folder and note, in the web's order: at each level the subfolders (each followed by what is
    /// inside it), then the notes that sit directly in that folder.
    var rows: [NoteTreeRow] {
        var result: [NoteTreeRow] = []
        let notesIn = Dictionary(grouping: notes, by: { $0.folderId ?? 0 })
        func walk(_ parent: Int?, _ depth: Int, _ ancestors: [Int]) {
            for f in NoteFolders.children(of: parent, in: folders) where depth < 20 {
                result.append(.folder(f, depth: depth, ancestors: ancestors))
                walk(f.id, depth + 1, ancestors + [f.id])
            }
            for n in notesIn[parent ?? 0] ?? [] { result.append(.note(n, depth: depth, ancestors: ancestors)) }
        }
        walk(nil, 0, [])
        return result
    }

    /// The rows on screen: those not inside a collapsed folder
    var visibleRows: [NoteTreeRow] { rows.filter { row in !row.ancestors.contains { collapsed.contains($0) } } }

    /// The notes in the order they appear, for the arrow keys: the search results, or the tree's notes
    var visibleNoteIDs: [Int] {
        if isFiltered { return notes.map(\.id) }
        return visibleRows.compactMap { if case .note(let n, _, _) = $0 { n.id } else { nil } }
    }

    func hasChildren(_ folder: Int) -> Bool {
        folders.contains { $0.parentId == folder } || notes.contains { $0.folderId == folder }
    }

    func toggleCollapsed(_ folder: Int) {
        if collapsed.contains(folder) { collapsed.remove(folder) } else { collapsed.insert(folder) }
    }

    // ── Loading ─────────────────────────────────────────────────────────────

    func load() async {
        do {
            let found = try await api.list(search: search.trimmingCharacters(in: .whitespaces))
            let tree = try await api.folders()
            notes = found
            folders = tree
            loaded = true
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    // ── Making, moving, deleting ────────────────────────────────────────────

    /// A blank note, or one started from a template (its type, starting title and text), in `folder`.
    /// Returns the new note's id, or nil with `error` set.
    @discardableResult
    func newNote(in folder: Int? = nil, template: NoteTemplate? = nil) async -> Int? {
        do {
            let id = try await api.createNote([
                "title": template?.startTitle ?? "Untitled", "type": template?.type ?? "note", "content": template?.content ?? "",
                "folderId": folder.map { $0 as Any } ?? NSNull(),
            ])
            await load()
            return id
        } catch { self.error = error.localizedDescription; return nil }
    }

    @discardableResult
    func newFolder(_ name: String, in parent: Int? = nil) async -> Bool {
        let text = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        return await change { try await self.api.createFolder(name: text, parentId: parent) }
    }

    func rename(folder id: Int, to name: String) async {
        let text = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        _ = await change { try await self.api.renameFolder(id: id, name: text) }
    }

    /// The folder's notes and subfolders move up one level; nothing else is deleted
    func delete(folder id: Int) async {
        if await change({ try await self.api.deleteFolder(id: id) }) { collapsed.remove(id) }
    }

    func move(note id: Int, to folder: Int?) async {
        guard notes.first(where: { $0.id == id })?.folderId != folder else { return }
        _ = await change { try await self.api.move(note: id, to: folder) }
    }

    func togglePin(_ id: Int) async { _ = await change { try await self.api.togglePin(id: id) } }

    func delete(note id: Int) async { _ = await change { try await self.api.deleteNote(id: id) } }

    /// Runs a change, then reloads so the tree shows what the server now has
    private func change(_ call: () async throws -> Void) async -> Bool {
        do {
            try await call()
            await load()
            return error == nil
        } catch { self.error = error.localizedDescription; return false }
    }
}
