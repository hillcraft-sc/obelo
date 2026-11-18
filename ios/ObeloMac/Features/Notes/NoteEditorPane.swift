import SwiftUI

/// The middle pane: the open note, with a title, Write | Preview, the formatting toolbar and the text
struct NoteEditorPane: View {
    @Environment(\.theme) private var theme
    @Bindable var model: NotesScreenModel
    let controller: KitMarkdownEditorController
    @Binding var detailsVisible: Bool

    var body: some View {
        Group {
            if let editor = model.editor {
                OpenNote(model: model, editor: editor, controller: controller, detailsVisible: $detailsVisible)
                    .id(editor.id)
            } else {
                VStack(spacing: 14) {
                    Text("Pick a note from the tree, or start a new one.").font(.system(size: 14)).foregroundStyle(theme.textMuted)
                    Button("New note") { Task { await model.newNote() } }.buttonStyle(KitButtonStyle(.secondary))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity)
        .clipped()
        .background(theme.page)
    }
}

private struct OpenNote: View {
    @Environment(\.theme) private var theme
    @Environment(AppState.self) private var app
    @Bindable var model: NotesScreenModel
    @Bindable var editor: NoteEditor
    let controller: KitMarkdownEditorController
    @Binding var detailsVisible: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let error = editor.error, editor.note == nil {
                KitEmptyState(message: error)
            } else if editor.note == nil {
                KitEmptyState(message: "Loading…")
            } else if editor.isLockedShut {
                lockedView
            } else {
                header
                modeRow
                if editor.drawMode {
                    drawing
                } else {
                    if !model.previewMode { KitFormatToolbar(controller: controller).padding(.horizontal, 16).padding(.bottom, 8) }
                    content
                }
            }
        }
        .kitFileDrop(isTargeted: $model.fileDropTargeted) { urls in Task { await model.attach(urls) } }
        .onChange(of: editor.snapshot) { editor.changed() }
        .onChange(of: editor.status) { _, status in if status == "Saved" { model.saved() } }
    }

    /// A locked note: its title, and a PIN field (web: the "This note is locked" form)
    private var lockedView: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let title = editor.note?.title { Text(title).font(.system(size: 18, weight: .semibold)).foregroundStyle(theme.textPrimary) }
            Label("This note is locked. Enter your PIN to edit it.", systemImage: "lock.fill")
                .font(.system(size: 14)).foregroundStyle(theme.textMuted)
            HStack(spacing: 8) {
                KitSecureField(placeholder: "PIN", text: $model.pin, isError: model.pinError != nil,
                               onSubmit: { Task { await model.unlock() } }, contentType: .oneTimeCode)
                    .frame(width: 160)
                    .onExitCommand { model.pin = "" }
                Button("Unlock") { Task { await model.unlock() } }
                    .buttonStyle(KitButtonStyle(.primary, busy: model.unlocking))
                    .disabled(model.pin.isEmpty)
            }
            if let error = model.pinError { Text(error).font(.system(size: 12)).foregroundStyle(theme.red400) }
        }
        .padding(24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Handwriting: the pen tools above the canvas (web: the Draw panel)
    private var drawing: some View {
        let paper = app.drawingPaper
        let doc = Binding(get: { editor.drawing ?? DrawingDoc(w: 0, h: DrawingDoc.defaultHeight, strokes: []) },
                          set: { editor.setDrawing($0) })
        return VStack(spacing: 8) {
            KitDrawingToolbar(color: $model.penColor, width: $model.penWidth, erasing: $model.erasing, paper: paper,
                              canUndo: !(editor.drawing?.strokes.isEmpty ?? true),
                              undo: { model.drawController.undo() }, clear: { model.confirmClearDrawing = true })
            KitDrawingCanvas(doc: doc, color: model.penColor, width: model.penWidth, erasing: model.erasing,
                             paper: paper, controller: model.drawController)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(theme.border2))
        }
        .padding(.horizontal, 16).padding(.bottom, 16)
        .kitConfirm("Clear the whole drawing?", isPresented: $model.confirmClearDrawing, confirmLabel: "Clear", destructive: true) {
            model.clearDrawing()
        }
    }

    // ── Title and save state ────────────────────────────────────────────────

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            KitTitleField(placeholder: "Untitled", text: $editor.title,
                          onSubmit: { controller.focus() }, focusRequest: $model.focusTitle)
            Text(editor.status).font(.system(size: 12)).foregroundStyle(theme.textMuted).lineLimit(1).fixedSize()
                .accessibilityLabel(editor.status.isEmpty ? "" : "Save state: \(editor.status)")
            KitIconButton(systemImage: "sidebar.right", label: detailsVisible ? "Hide details (⌘⌥I)" : "Show details (⌘⌥I)") { detailsVisible.toggle() }
        }
        .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 8)
    }

    private var modeRow: some View {
        HStack(spacing: 10) {
            if editor.canDraw {
                KitPillSelector(options: [(value: false, label: "Text"), (value: true, label: "Draw")],
                                selection: Binding(get: { editor.drawMode }, set: { model.setDrawMode($0) }), label: "Text or draw")
            }
            if !editor.drawMode {
                KitPillSelector(options: [(value: false, label: "Write"), (value: true, label: "Preview")],
                                selection: $model.previewMode, label: "Write or preview")
            }
            Spacer()
        }
        .padding(.horizontal, 16).padding(.bottom, 8)
    }

    // ── The text ────────────────────────────────────────────────────────────

    @ViewBuilder private var content: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        Group {
            if model.previewMode {
                ScrollView {
                    if editor.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Nothing to preview yet.").font(.system(size: 14)).italic().foregroundStyle(theme.textMuted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        MarkdownView(text: editor.content) { line, done in
                            if let updated = MarkdownView.toggling(editor.content, line: line, done: done) { editor.content = updated }
                        }
                    }
                }
                .padding(18)
            } else {
                KitMarkdownEditor(text: $editor.content, controller: controller)
            }
        }
        .background(theme.surface, in: shape)
        .overlay(shape.strokeBorder(theme.border1))
        .padding(.horizontal, 16).padding(.bottom, 16)
    }
}
