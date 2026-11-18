import Foundation
import Testing
@testable import ObeloShared

func makeNoteSummary(_ id: Int, _ title: String = "Note", folder: Int? = nil, pinned: Bool = false, locked: Bool = false) -> NoteSummary {
    var obj: [String: Any] = [
        "id": id, "type": "note", "title": title, "preview": "", "tags": [String](), "pinned": pinned, "flaggedForReview": false,
        "locked": locked, "hasDrawing": false, "private": false,
        "createdAt": "2026-11-14T10:00:00.000Z", "updatedAt": "2026-11-14T10:00:00.000Z",
    ]
    if let folder { obj["folderId"] = folder }
    let d = JSONDecoder()
    d.dateDecodingStrategy = .custom { dec in
        try Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(try dec.singleValueContainer().decode(String.self))
    }
    return try! d.decode(NoteSummary.self, from: JSONSerialization.data(withJSONObject: obj))
}

func makeFolder(_ id: Int, _ name: String, parent: Int? = nil) -> NoteFolder {
    var obj: [String: Any] = ["id": id, "name": name]
    if let parent { obj["parentId"] = parent }
    return try! JSONDecoder().decode(NoteFolder.self, from: JSONSerialization.data(withJSONObject: obj))
}

@MainActor
final class StubNotesAPI: NotesAPI {
    struct Failure: LocalizedError { var errorDescription: String? { "Stub failure" } }
    var notes: [NoteSummary]
    var folders: [NoteFolder]
    var calls: [String] = []
    var failNext = false
    var lastBody: [String: Any] = [:]
    var nextId = 100

    init(notes: [NoteSummary] = [], folders: [NoteFolder] = []) { self.notes = notes; self.folders = folders }

    private func record(_ s: String) throws { calls.append(s); if failNext { failNext = false; throw Failure() } }

    func list(search: String?) async throws -> [NoteSummary] {
        try record("list \(search ?? "-")")
        guard let search, !search.isEmpty else { return notes }
        return notes.filter { $0.title.localizedCaseInsensitiveContains(search) }
    }
    func folders() async throws -> [NoteFolder] { try record("folders"); return folders }
    func createNote(_ body: [String: Any]) async throws -> Int { try record("createNote"); lastBody = body; nextId += 1; return nextId }
    func createFolder(name: String, parentId: Int?) async throws {
        try record("createFolder \(name) \(parentId.map(String.init) ?? "-")")
        nextId += 1; folders.append(makeFolder(nextId, name, parent: parentId))
    }
    func renameFolder(id: Int, name: String) async throws {
        try record("renameFolder \(id) \(name)")
        if let i = folders.firstIndex(where: { $0.id == id }) { folders[i].name = name }
    }
    func deleteFolder(id: Int) async throws {
        try record("deleteFolder \(id)")
        let parent = folders.first { $0.id == id }?.parentId
        folders.removeAll { $0.id == id }
        folders = folders.map { $0.parentId == id ? NoteFolder(id: $0.id, name: $0.name, parentId: parent, path: $0.path) : $0 }
    }
    func move(note: Int, to folder: Int?) async throws {
        try record("move \(note) \(folder.map(String.init) ?? "top")")
        if let i = notes.firstIndex(where: { $0.id == note }) {
            let n = notes[i]
            notes[i] = makeNoteSummary(n.id, n.title, folder: folder, pinned: n.pinned, locked: n.locked)
        }
    }
    func togglePin(id: Int) async throws {
        try record("pin \(id)")
        if let i = notes.firstIndex(where: { $0.id == id }) {
            let n = notes[i]
            notes[i] = makeNoteSummary(n.id, n.title, folder: n.folderId, pinned: !n.pinned, locked: n.locked)
        }
    }
    func deleteNote(id: Int) async throws { try record("deleteNote \(id)"); notes.removeAll { $0.id == id } }
}

@MainActor
struct NotesStoreTests {
    /// Work / (Plans / roadmap), Home; notes: loose, Work's "budget", Plans' "roadmap", Home's "chores" (pinned)
    func store() -> (NotesStore, StubNotesAPI) {
        let api = StubNotesAPI(
            notes: [makeNoteSummary(1, "loose"), makeNoteSummary(2, "budget", folder: 10), makeNoteSummary(3, "roadmap", folder: 11),
                    makeNoteSummary(4, "chores", folder: 12, pinned: true)],
            folders: [makeFolder(12, "Home"), makeFolder(10, "Work"), makeFolder(11, "Plans", parent: 10)])
        return (NotesStore(api: api), api)
    }

    @Test func theTreeIsSubfoldersFirstThenNotesAtEveryLevel() async {
        let (s, _) = store()
        await s.load()
        #expect(s.rows.map(\.id) == ["f12", "n4", "f10", "f11", "n3", "n2", "n1"])
    }

    @Test func rowsKnowTheirDepthAndTheFoldersAboveThem() async {
        let (s, _) = store()
        await s.load()
        guard case .note(_, let depth, let ancestors) = s.rows.first(where: { $0.id == "n3" })! else { Issue.record("not a note"); return }
        #expect(depth == 2 && ancestors == [10, 11])
    }

    @Test func aCollapsedFolderHidesEverythingInsideItAndNothingElse() async {
        let (s, _) = store()
        await s.load()
        s.toggleCollapsed(10)
        #expect(s.visibleRows.map(\.id) == ["f12", "n4", "f10", "n1"])
        s.toggleCollapsed(10)
        s.toggleCollapsed(11)
        #expect(s.visibleRows.map(\.id) == ["f12", "n4", "f10", "f11", "n2", "n1"])
    }

    @Test func theArrowKeysWalkTheVisibleNotesInOrder() async {
        let (s, _) = store()
        await s.load()
        #expect(s.visibleNoteIDs == [4, 3, 2, 1])
        s.toggleCollapsed(10)
        #expect(s.visibleNoteIDs == [4, 1])
    }

    @Test func pinnedNotesAreListedSeparately() async {
        let (s, _) = store()
        await s.load()
        #expect(s.pinned.map(\.id) == [4])
    }

    @Test func searchingAsksTheServerAndShowsAFlatList() async {
        let (s, api) = store()
        s.search = "  road "
        #expect(s.isFiltered)
        await s.load()
        #expect(api.calls.contains("list road"))
        #expect(s.visibleNoteIDs == [3])
    }

    @Test func aFailedLoadKeepsWhatWasThereAndSetsAnError() async {
        let (s, api) = store()
        await s.load()
        api.failNext = true
        await s.load()
        #expect(s.notes.count == 4 && s.error == "Stub failure")
    }

    @Test func aNewNoteGetsItsFolderAndTheTemplatesFields() async {
        let (s, api) = store()
        await s.load()
        let template = NoteTemplate(id: "t", label: "Standup", type: "journal", title: "x", dateTitle: false, content: "## Done", startTitle: "Standup — ")
        let id = await s.newNote(in: 10, template: template)
        #expect(id != nil)
        #expect(api.lastBody["title"] as? String == "Standup — " && api.lastBody["type"] as? String == "journal")
        #expect(api.lastBody["content"] as? String == "## Done" && api.lastBody["folderId"] as? Int == 10)
        _ = await s.newNote()
        #expect(api.lastBody["title"] as? String == "Untitled" && api.lastBody["folderId"] is NSNull)
    }

    @Test func aFailedNewNoteReturnsNilWithAnError() async {
        let (s, api) = store()
        api.failNext = true
        #expect(await s.newNote() == nil)
        #expect(s.error == "Stub failure")
    }

    @Test func newFoldersAreTrimmedAndEmptyOnesIgnored() async {
        let (s, api) = store()
        await s.load()
        #expect(!(await s.newFolder("   ")))
        #expect(await s.newFolder("  Ideas ", in: 10))
        #expect(api.calls.contains("createFolder Ideas 10"))
        #expect(s.folders.contains { $0.name == "Ideas" && $0.parentId == 10 })
    }

    @Test func renamingAFolderUpdatesTheTree() async {
        let (s, _) = store()
        await s.load()
        await s.rename(folder: 10, to: "Office")
        #expect(s.folders.first { $0.id == 10 }?.name == "Office")
    }

    @Test func deletingAFolderMovesItsContentsUpAndUnfoldsIt() async {
        let (s, api) = store()
        await s.load()
        s.toggleCollapsed(10)
        await s.delete(folder: 10)
        #expect(api.calls.contains("deleteFolder 10"))
        #expect(!s.collapsed.contains(10))
        #expect(s.folders.first { $0.id == 11 }?.parentId == nil)
    }

    @Test func movingANoteReloadsAndMovingItWhereItIsDoesNothing() async {
        let (s, api) = store()
        await s.load()
        await s.move(note: 1, to: 10)
        #expect(s.notes.first { $0.id == 1 }?.folderId == 10)
        let calls = api.calls.count
        await s.move(note: 1, to: 10)
        #expect(api.calls.count == calls)
        await s.move(note: 1, to: nil)
        #expect(s.notes.first { $0.id == 1 }?.folderId == nil)
    }

    @Test func pinningAndDeletingANoteReload() async {
        let (s, _) = store()
        await s.load()
        await s.togglePin(1)
        #expect(s.pinned.map(\.id).sorted() == [1, 4])
        await s.delete(note: 1)
        #expect(!s.notes.contains { $0.id == 1 })
    }

    @Test func aRefusedChangeSetsAnErrorAndKeepsTheTree() async {
        let (s, api) = store()
        await s.load()
        api.failNext = true
        await s.togglePin(1)
        #expect(s.error == "Stub failure" && s.notes.count == 4)
    }

    @Test func aFolderKnowsWhetherItHasAnythingInIt() async {
        let (s, api) = store()
        await s.load()
        #expect(s.hasChildren(10) && s.hasChildren(12))
        api.folders.append(makeFolder(30, "Empty"))
        await s.load()
        #expect(!s.hasChildren(30))
    }
}
