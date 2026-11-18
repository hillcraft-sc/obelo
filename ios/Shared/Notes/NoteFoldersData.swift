import SwiftUI

struct NoteFolder: Codable, Identifiable, Hashable {
    let id: Int
    var name: String
    let parentId: Int?
    var path: String?
}

/// What the notes list shows: every note, or one folder's notes (nil = the top level)
enum NoteScope: Hashable {
    case all
    case folder(Int?)

    /// Stored in AppStorage so Notes reopens where you left it
    var raw: String {
        switch self {
        case .all: "all"
        case .folder(nil): "top"
        case .folder(let id?): "f\(id)"
        }
    }

    init(raw: String) {
        if raw == "top" { self = .folder(nil) }
        else if raw.hasPrefix("f"), let id = Int(raw.dropFirst()) { self = .folder(id) }
        else { self = .all }
    }
}

enum NoteFolders {
    nonisolated struct Response: Decodable { let folders: [NoteFolder] }
    struct One: Decodable { let folder: NoteFolder }

    static func load() async throws -> [NoteFolder] {
        let r: Response = try await APIClient.shared.get("/folders")
        return r.folders
    }

    /// Folders in tree order (each folder, then its subfolders), with their depth
    static func tree(_ folders: [NoteFolder]) -> [(folder: NoteFolder, depth: Int)] {
        let byParent = Dictionary(grouping: folders, by: { $0.parentId ?? 0 })
        var rows: [(NoteFolder, Int)] = []
        func walk(_ parent: Int, _ depth: Int) {
            for f in (byParent[parent] ?? []).sorted(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending }) {
                rows.append((f, depth))
                if depth < 20 { walk(f.id, depth + 1) }
            }
        }
        walk(0, 0)
        return rows
    }

    static func children(of parent: Int?, in folders: [NoteFolder]) -> [NoteFolder] {
        folders.filter { $0.parentId == parent }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func path(_ id: Int?, in folders: [NoteFolder]) -> String {
        guard let id else { return "Top level" }
        if let f = folders.first(where: { $0.id == id }) { return f.path ?? f.name }
        return "Folder"
    }

    /// The folder and every folder inside it
    static func subtree(_ id: Int, in folders: [NoteFolder]) -> Set<Int> {
        var ids: Set<Int> = [id]
        var added = true
        while added {
            added = false
            for f in folders where !ids.contains(f.id) {
                if let p = f.parentId, ids.contains(p) { ids.insert(f.id); added = true }
            }
        }
        return ids
    }

    // ── Dragging notes onto folders ─────────────────────────────────────────
    // A note is dragged as the text "obelo-note:<id>", so text dragged in from elsewhere is ignored.
    static func dragText(_ noteID: Int) -> String { "obelo-note:\(noteID)" }
    static func noteID(fromDrag text: String) -> Int? {
        guard text.hasPrefix("obelo-note:") else { return nil }
        return Int(text.dropFirst("obelo-note:".count))
    }

    /// Moves a note to a folder (nil = the top level)
    static func move(note: Int, to folder: Int?) async throws {
        try await APIClient.shared.post("/notes/\(note)/move", ["folderId": folder.map { $0 as Any } ?? NSNull()])
    }
}
