import AppKit
import SwiftUI

/// Notes 4b: handwriting, attachments, locked notes and thoughts. The calls are the shared `NoteEditor`'s;
/// this holds what the screen adds (reading dropped files, opening an attachment, the messages).
extension NotesScreenModel {
    // ── Handwriting ─────────────────────────────────────────────────────────

    /// Text | Draw. A drawing with strokes in it can't be swapped for text without losing it, so go back to
    /// Text by clearing first (the web throws the drawing away when you switch; this asks you to).
    func setDrawMode(_ on: Bool) {
        guard let e = editor else { return }
        if on {
            guard e.canDraw else { return }
            e.drawMode = true
        } else if e.drawing?.strokes.isEmpty ?? true {
            e.drawMode = false
        } else {
            message = "Clear the drawing to go back to text."
            messageIsError = false
        }
    }

    func clearDrawing() {
        editor?.setDrawing(DrawingDoc(w: editor?.drawing?.w ?? 0, h: DrawingDoc.defaultHeight, strokes: []))
    }

    // ── Locked notes ────────────────────────────────────────────────────────

    func unlock() async {
        guard let e = editor, !pin.isEmpty, !unlocking else { return }
        unlocking = true
        defer { unlocking = false }
        do {
            try await e.unlock(pin: pin)
            pin = ""
            pinError = nil
        } catch {
            pinError = error.localizedDescription
        }
    }

    /// Locks the open note (the web's Lock button): saved first, then shown behind the PIN
    func lockOpenNote() async {
        guard let e = editor else { return }
        do {
            try await e.lock()
            pin = ""
            pinError = nil
            await store.load()
        } catch {
            message = error.localizedDescription
            messageIsError = true
        }
    }

    // ── Attachments ─────────────────────────────────────────────────────────

    /// Attaches files (the picker, or dragged from Finder). Each is checked first against what the server accepts.
    func attach(_ urls: [URL]) async {
        guard let e = editor, e.note != nil, !e.isLockedShut, !urls.isEmpty else { return }
        uploading += urls.count
        var added = 0
        var problems: [String] = []
        for url in urls {
            defer { uploading -= 1 }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let name = url.lastPathComponent
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            guard case .accepted(let mime) = NoteAttachmentRules.check(filename: name, byteCount: size) else {
                if case .refused(let why) = NoteAttachmentRules.check(filename: name, byteCount: size) { problems.append(why) }
                continue
            }
            guard let data = try? Data(contentsOf: url) else { problems.append("\u{201C}\(name)\u{201D} couldn't be read."); continue }
            do {
                try await e.addAttachment(data: data, filename: name, mimeType: mime)
                added += 1
            } catch {
                problems.append(error.localizedDescription)
            }
        }
        if let first = problems.first {
            message = problems.count == 1 ? first : "\(problems.count) files couldn't be attached. \(first)"
            messageIsError = true
        } else if added > 0 {
            message = added == 1 ? "Attached" : "\(added) files attached"
            messageIsError = false
        }
    }

    func open(_ attachment: Note.Attachment) async {
        if NoteAttachmentRules.isImage(attachment.mimeType) { viewingAttachment = attachment; return }
        guard let file = await download(attachment) else { return }
        NSWorkspace.shared.open(file)
        // The copy is only for the other app to read; remove it after a while
        Task {
            try? await Task.sleep(for: .seconds(300))
            try? FileManager.default.removeItem(at: file.deletingLastPathComponent())
        }
    }

    func saveAs(_ attachment: Note.Attachment) async {
        guard let file = await download(attachment) else { return }
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = NoteAttachmentRules.displayName(forURL: attachment.url)
        guard panel.runModal() == .OK, let target = panel.url else { return }
        do {
            try? FileManager.default.removeItem(at: target)
            try FileManager.default.copyItem(at: file, to: target)
        } catch {
            message = "Couldn't save the file."
            messageIsError = true
        }
    }

    private func download(_ attachment: Note.Attachment) async -> URL? {
        do {
            let data = try await APIClient.shared.data(path: attachment.url)
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let file = dir.appendingPathComponent(NoteAttachmentRules.displayName(forURL: attachment.url))
            try data.write(to: file)
            return file
        } catch {
            message = error.localizedDescription
            messageIsError = true
            return nil
        }
    }

    func confirmRemoveAttachment(_ a: Note.Attachment) async {
        guard let e = editor else { return }
        pendingRemoveAttachment = nil
        do { try await e.removeAttachment(a.id) } catch { message = error.localizedDescription; messageIsError = true }
    }

    // ── Thoughts ────────────────────────────────────────────────────────────

    func addThought() async {
        let text = newThought.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let e = editor, !text.isEmpty else { return }
        do {
            try await e.addThought(text)
            newThought = ""
        } catch {
            message = error.localizedDescription
            messageIsError = true
        }
    }

    func confirmDeleteThought(_ id: Int) async {
        guard let e = editor else { return }
        pendingDeleteThought = nil
        do { try await e.deleteThought(id) } catch { message = error.localizedDescription; messageIsError = true }
    }
}
