import AppKit
import SwiftUI

/// What the Notes screen does, so the views only draw and call: which note is open, opening and leaving
/// one (the shared `NoteEditor` saves), making notes and folders, drag and drop, and what waits for a
/// confirmation. The list is `NotesStore`; the open note is `NoteEditor`.
@MainActor @Observable
final class NotesScreenModel {
    let store: NotesStore
    let templates = NoteTemplatesStore()
    private(set) var editor: NoteEditor?
    private(set) var allTags: [String] = []

    /// The open note, and the folder a new note goes into (the last folder you clicked)
    var selectedID: Int?
    var selectedFolder: Int?
    var previewMode = false
    /// The row a dragged note is over
    var dropTarget: String?

    // Asking for a name, and for confirmation
    enum Naming: Identifiable, Equatable {
        case newFolder(parent: Int?), rename(folder: Int), saveTemplate
        var id: String {
            switch self {
            case .newFolder(let p): "new\(p.map(String.init) ?? "top")"
            case .rename(let f): "rename\(f)"
            case .saveTemplate: "template"
            }
        }
    }
    var naming: Naming? { didSet { if naming != nil { lastNaming = naming } } }
    /// What the name box was for, kept because SwiftUI clears `naming` as the alert closes, before OK's action runs
    private var lastNaming: Naming?
    var nameText = ""
    var pendingDeleteNote: Int?
    var pendingDeleteFolder: Int?

    var focusTitle = false
    var focusSearch = false

    // Handwriting: the pen
    var penColor = DrawingRenderer.colors[0]
    var penWidth: Double = 3
    var erasing = false
    var confirmClearDrawing = false
    let drawController = KitDrawingController()

    // Attachments
    var uploading = 0
    var fileDropTargeted = false
    var showFilePicker = false
    var viewingAttachment: Note.Attachment?
    var pendingRemoveAttachment: Note.Attachment?

    // Locked notes and thoughts
    var pin = ""
    var pinError: String?
    var unlocking = false
    var newThought = ""
    var pendingDeleteThought: Int?

    private var searchTask: Task<Void, Never>?
    /// How the open note's fields are filled: from the server, or from sample data when drawing the screen offline
    private let loadEditor: (NoteEditor) async -> Void

    init(store: NotesStore = NotesStore(), loadEditor: @escaping (NoteEditor) async -> Void = { await $0.load() }) {
        self.store = store
        self.loadEditor = loadEditor
    }

    // ── Loading ─────────────────────────────────────────────────────────────

    func load() async {
        await store.load()
        await templates.load()
        if allTags.isEmpty { await loadTags() }
    }

    private func loadTags() async {
        struct Tags: Decodable { let tags: [String] }
        allTags = ((try? await APIClient.shared.get("/tags")) as Tags?)?.tags ?? []
    }

    /// Search as you type, after a short pause
    func searchChanged() {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await store.load()
        }
    }

    // ── The open note ───────────────────────────────────────────────────────

    /// Opens a note (nil closes). The note being left is saved first, or deleted if it was a new note left blank.
    func open(_ id: Int?, isNew: Bool = false) async {
        if id == selectedID, editor != nil || id == nil { return }
        await leave()
        selectedID = id
        previewMode = false
        guard let id else { editor = nil; return }
        let e = NoteEditor(id: id, isNew: isNew)
        editor = e
        await loadEditor(e)
        if e.type != "quote", e.note != nil { /* plain notes open in the writing area */ }
        if isNew { focusTitle = true }
    }

    /// Saves the open note (or deletes it, if it is a new note left blank) and lets go of it
    func leave() async {
        guard let e = editor else { return }
        if e.isNew, e.note != nil, !e.isLockedShut, e.isBlank {
            try? await e.delete()
            await store.load()
        } else {
            _ = await e.flush()
        }
    }

    /// Saves the open note now (before a move, or when leaving the screen)
    func flush() async { _ = await editor?.flush() }

    /// After a save, the tree shows the note's new title, folder and pin
    func saved() { Task { await store.load() } }

    // ── Making and changing ─────────────────────────────────────────────────

    func newNote(template: NoteTemplate? = nil) async {
        guard let id = await store.newNote(in: selectedFolder, template: template) else { return }
        await open(id, isNew: true)
    }

    func submitName() async {
        guard let naming = naming ?? lastNaming else { return }
        let text = nameText
        self.naming = nil
        lastNaming = nil
        nameText = ""
        switch naming {
        case .newFolder(let parent): _ = await store.newFolder(text, in: parent)
        case .rename(let folder): await store.rename(folder: folder, to: text)
        case .saveTemplate: await saveTemplate(named: text)
        }
    }

    func askNewFolder(in parent: Int? = nil) { nameText = ""; naming = .newFolder(parent: parent) }

    func askRename(_ folder: NoteFolder) { nameText = folder.name; naming = .rename(folder: folder.id) }

    func askSaveTemplate() {
        nameText = (editor?.title ?? "") == "Untitled" ? "" : editor?.title ?? ""
        naming = .saveTemplate
    }

    /// Keeps the open note's type, title and text as a template (the web's "Save as template")
    private func saveTemplate(named name: String) async {
        guard let e = editor else { return }
        var draft = NoteTemplateDraft()
        draft.label = name
        draft.type = NoteTemplatesStore.types.contains(e.type) ? e.type : "note"
        draft.title = e.title
        draft.content = e.content
        let made = await templates.create(draft)
        message = made != nil ? "Saved the template \u{201C}\(name.trimmingCharacters(in: .whitespaces))\u{201D}" : (templates.error ?? "Couldn't save the template")
        messageIsError = made == nil
    }

    /// A short message for the screen's toast
    var message: String?
    var messageIsError = false

    func confirmDeleteNote(_ id: Int) async {
        pendingDeleteNote = nil
        if id == selectedID, let e = editor {
            try? await e.delete()
            editor = nil
            selectedID = nil
        } else {
            await store.delete(note: id)
        }
        await store.load()
    }

    func confirmDeleteFolder(_ id: Int) async {
        pendingDeleteFolder = nil
        if selectedFolder == id { selectedFolder = nil }
        await flush()
        await store.delete(folder: id)
    }

    func togglePin(_ id: Int) async {
        if id == selectedID, let e = editor {
            e.pinned.toggle()
            e.changed()
        } else {
            await store.togglePin(id)
        }
    }

    /// Dragging a note onto a folder, or onto "Top level"
    func move(note id: Int, to folder: Int?) async {
        if id == selectedID, let e = editor {
            _ = await e.flush()
            await store.move(note: id, to: folder)
            e.folderId = folder   // so the next autosave doesn't put it back
            e.changed()
        } else {
            await store.move(note: id, to: folder)
        }
    }

    /// Arrow keys in the tree
    func step(_ delta: Int) async {
        let ids = store.visibleNoteIDs
        guard !ids.isEmpty else { return }
        let current = selectedID.flatMap { ids.firstIndex(of: $0) }
        let next = current.map { min(max($0 + delta, 0), ids.count - 1) } ?? (delta >= 0 ? 0 : ids.count - 1)
        await open(ids[next])
    }

    /// "Open this note" from another screen (a row in Today, a note just made in Capture)
    func show(_ id: Int) async {
        if store.isFiltered { store.search = ""; await store.load() }
        await open(id)
    }
}
