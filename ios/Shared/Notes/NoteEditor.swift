import SwiftUI

/// One open note: its fields, and autosave. The rules match the web workspace: save 1.5 s after the
/// last change; a change made while a save is in flight gets its own save; leaving saves at once.
/// PUT /notes/:id overwrites every field it gets, so every save sends all of them, and the drawing
/// for a handwritten note.
@MainActor @Observable
final class NoteEditor {
    let id: Int
    /// Made with New note: a blank title shows the placeholder, and a note left empty is deleted
    let isNew: Bool

    var note: Note?
    var error: String?

    var title = ""
    var content = ""
    var author = ""
    var source = ""
    var type = "note"
    var tags: [String] = []
    var pinned = false
    var isPrivate = false
    var flagged = false
    var reviewDate: String?
    var folderId: Int?
    var drawMode = false
    /// Every folder, for the folder's name and the Details picker
    var folders: [NoteFolder] = []
    private(set) var drawing: DrawingDoc?
    private(set) var drawingJSON: String?

    /// "Saving…", "Saved", or why the note wasn't saved
    var status = ""
    var deleted = false
    /// The drawing editor covers the screen; the note isn't being left
    var coverOpen = false

    struct Snapshot: Equatable {
        var title, content, author, source, type: String
        var tags: [String]
        var pinned, isPrivate, flagged: Bool
        var reviewDate: String?
        var folderId: Int?
        var drawMode: Bool
        var drawing: String?
    }

    private var saved: Snapshot?
    private var saving = false
    private var timer: Task<Void, Never>?

    init(id: Int, isNew: Bool) {
        self.id = id
        self.isNew = isNew
    }

    var isLockedShut: Bool { note?.locked == true && note?.content == nil }
    var canDraw: Bool { type != "quote" && note?.locked != true }
    var folderPath: String? { folderId.map { NoteFolders.path($0, in: folders) } }

    var snapshot: Snapshot {
        Snapshot(title: title, content: content, author: author, source: source, type: type, tags: tags,
                 pinned: pinned, isPrivate: isPrivate, flagged: flagged, reviewDate: reviewDate, folderId: folderId,
                 drawMode: drawMode, drawing: drawMode ? drawingJSON : nil)
    }

    /// Nothing written: a New note left like this is deleted
    var isBlank: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !drawMode && (note?.attachments.isEmpty ?? true) && (note?.thoughts.isEmpty ?? true)
    }

    nonisolated struct R: Decodable { let note: Note }

    func load() async {
        do {
            async let one: R = APIClient.shared.get("/notes/\(id)")
            async let tree = try? NoteFolders.load()
            let (r, f) = try await (one, tree)
            if let f { folders = f }
            if r.note.locked && r.note.content == nil { note = r.note; saved = nil } else { apply(r.note) }
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    /// Fills the fields from the server's note
    private func apply(_ n: Note) {
        note = n
        title = isNew && n.title == "Untitled" ? "" : n.title
        content = n.content ?? ""
        author = n.author ?? ""
        source = n.source ?? ""
        type = n.type
        tags = n.tags
        pinned = n.pinned
        isPrivate = n.private
        flagged = n.flaggedForReview
        reviewDate = n.reviewDate
        folderId = n.folderId
        if n.hasDrawing, let doc = DrawingDoc.decode(n.drawingData) {
            drawing = doc; drawingJSON = n.drawingData; drawMode = true
        } else {
            drawing = nil; drawingJSON = nil; drawMode = false
        }
        saved = snapshot
        status = ""
    }

    /// Fills the fields from a note already in hand (tests, and the Mac screen's sample data)
    func adopt(_ n: Note) { apply(n) }

    func setDrawing(_ doc: DrawingDoc) {
        drawing = doc.strokes.isEmpty ? nil : doc
        drawingJSON = drawing?.encoded()
    }

    /// Called whenever a field changes
    func changed() {
        guard let saved, snapshot != saved else { return }
        schedule(after: 1.5)
    }

    private func schedule(after seconds: Double) {
        timer?.cancel()
        timer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            // save() cancels the pending timer; this task is that timer, so it lets go of itself first
            // (cancelling it would cancel the save's own request)
            self?.timer = nil
            await self?.save()
        }
    }

    /// Saves now. Returns true when the note is saved, or had nothing to save.
    @discardableResult
    func save() async -> Bool {
        timer?.cancel()
        guard let saved, !isLockedShut else { return true }
        let snap = snapshot
        guard snap != saved else { return true }
        // A save is in flight: it saves again when it finishes, if anything changed meanwhile
        guard !saving else { return false }
        if snap.drawMode && snap.drawing == nil {
            status = "Draw something to save"
            return false
        }
        saving = true
        status = "Saving…"
        defer { saving = false }
        do {
            let r: R = try await APIClient.shared.post("/notes/\(id)", body(snap), method: "PUT")
            self.saved = snap
            var updated = r.note
            if updated.locked && updated.content == nil { updated.content = snap.content }
            note = updated
            if snapshot != snap {
                schedule(after: 0.3)
            } else {
                status = "Saved"
            }
            return true
        } catch {
            status = (error as? LocalizedError)?.errorDescription ?? "Not saved"
            return false
        }
    }

    /// Waits for a save in flight, then saves what's left
    @discardableResult
    func flush() async -> Bool {
        timer?.cancel()
        for _ in 0..<100 where saving { try? await Task.sleep(for: .milliseconds(50)) }
        return await save()
    }

    private func body(_ s: Snapshot) -> [String: Any] {
        var b: [String: Any] = [
            "type": s.type,
            "title": s.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled" : s.title,
            "content": s.content, "source": s.source, "author": s.author, "tags": s.tags,
            "pinned": s.pinned, "private": s.isPrivate, "flaggedForReview": s.flagged,
            "reviewDate": s.reviewDate ?? NSNull(),
            "folderId": s.folderId.map { $0 as Any } ?? NSNull(),
        ]
        if s.drawMode, let d = s.drawing {
            b["noteMode"] = "draw"
            b["drawingData"] = d
        }
        return b
    }

    func unlock(pin: String) async throws {
        let r: R = try await APIClient.shared.post("/notes/\(id)/unlock", ["pin": pin])
        apply(r.note)
    }

    func lock() async throws {
        guard await flush() else { throw EditorError.notSaved }
        try await APIClient.shared.post("/notes/\(id)/lock")
        await load()
    }

    func delete() async throws {
        timer?.cancel()
        try await APIClient.shared.delete("/notes/\(id)")
        saved = nil
        deleted = true
    }

    func addThought(_ text: String) async throws {
        struct T: Decodable { let thought: Note.Thought }
        let r: T = try await APIClient.shared.post("/notes/\(id)/thoughts", ["content": text])
        note?.thoughts.append(r.thought)
    }

    /// Uploads a file as an attachment of this note (the caller has checked `NoteAttachmentRules`)
    @discardableResult
    func addAttachment(data: Data, filename: String, mimeType: String) async throws -> Note.Attachment {
        struct A: Decodable { let attachment: Note.Attachment }
        let r: A = try await APIClient.shared.upload("/notes/\(id)/attachments", field: "photo", data: data, filename: filename, mimeType: mimeType)
        note?.attachments.append(r.attachment)
        return r.attachment
    }

    func removeAttachment(_ attachmentID: Int) async throws {
        try await APIClient.shared.delete("/notes/\(id)/attachments/\(attachmentID)")
        note?.attachments.removeAll { $0.id == attachmentID }
    }

    func deleteThought(_ thoughtID: Int) async throws {
        try await APIClient.shared.delete("/notes/\(id)/thoughts/\(thoughtID)")
        note?.thoughts.removeAll { $0.id == thoughtID }
    }

    enum EditorError: LocalizedError {
        case notSaved
        var errorDescription: String? { "The note couldn't be saved. Try again." }
    }
}
