import SwiftUI

/// The right pane (web: Details): folder, type, tags, flags, "Save as template", delete
struct NoteDetailsPane: View {
    @Environment(\.theme) private var theme
    @Bindable var model: NotesScreenModel

    var body: some View {
        Group {
            if let editor = model.editor, editor.note != nil, !editor.isLockedShut {
                Details(model: model, editor: editor).id(editor.id)
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.surface.opacity(0.4))
    }
}

private struct Details: View {
    @Environment(\.theme) private var theme
    @Environment(AppState.self) private var app
    @Bindable var model: NotesScreenModel
    @Bindable var editor: NoteEditor

    private var folderOptions: [(value: Int?, label: String)] {
        [(value: nil, label: "Top level")]
            + model.store.folders.sorted { ($0.path ?? $0.name) < ($1.path ?? $1.name) }.map { (value: $0.id, label: $0.path ?? $0.name) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                KitGroupLabel(text: "Details")
                KitFieldLabel(text: "Folder") {
                    KitSelect(options: folderOptions, selection: $editor.folderId, label: "Folder")
                }
                KitFieldLabel(text: "Type") {
                    KitPillSelector(options: NoteTemplatesStore.types.map { (value: $0, label: NoteTemplatesStore.typeLabels[$0] ?? $0) },
                                    selection: $editor.type, label: "Type")
                }
                if editor.type == "quote" {
                    KitFieldLabel(text: "Source") { KitTextField(placeholder: "Book, podcast, article…", text: $editor.source) }
                    KitFieldLabel(text: "Author") { KitTextField(placeholder: "Author name", text: $editor.author) }
                }
                KitFieldLabel(text: "Tags") { KitTagPicker(tags: $editor.tags, suggestions: model.allTags) }
                    .zIndex(1)
                VStack(alignment: .leading, spacing: 8) {
                    KitCheckbox(title: "Pinned", isOn: $editor.pinned)
                    KitCheckbox(title: "Private", isOn: $editor.isPrivate)
                    KitCheckbox(title: "Flag for review", isOn: $editor.flagged)
                    if editor.flagged {
                        KitFieldLabel(text: "Review on") {
                            KitOptionalDateField(components: .date, value: reviewDate, label: "Review date", emptyLabel: "Set date")
                        }
                        .padding(.leading, 20)
                    }
                }
                HStack(spacing: 8) {
                    if editor.note?.locked != true && !editor.drawMode {
                        Button("Save as template") { model.askSaveTemplate() }
                            .buttonStyle(KitButtonStyle(.secondary, small: true))
                            .help("Keep this note's type, title and text as a starting point for new notes")
                    }
                    if editor.note?.locked != true && !editor.drawMode && app.me?.canLockNotes == true {
                        Button("Lock") { Task { await model.lockOpenNote() } }
                            .buttonStyle(KitButtonStyle(.secondary, small: true))
                            .help("Hide this note behind your PIN")
                    }
                }
                KitDivider()
                attachments
                KitDivider()
                thoughts
                KitDivider()
                HStack {
                    if let note = editor.note {
                        Text("Created \(Fmt.monthDayYear(note.createdAt))").font(.system(size: 11)).foregroundStyle(theme.textMuted)
                    }
                    Spacer()
                    Button("Delete note") { model.pendingDeleteNote = editor.id }
                        .buttonStyle(KitButtonStyle(.danger, small: true))
                }
            }
            .padding(16)
        }
        .scrollEdgeEffectHidden(true, for: .top)
    }

    // ── Attachments ─────────────────────────────────────────────────────────

    private var attachments: some View {
        let all = editor.note?.attachments ?? []
        let images = all.filter { NoteAttachmentRules.isImage($0.mimeType) }
        let files = all.filter { !NoteAttachmentRules.isImage($0.mimeType) }
        return VStack(alignment: .leading, spacing: 8) {
            KitGroupLabel(text: "Attachments")
            if all.isEmpty && model.uploading == 0 {
                Text("No attachments yet.").font(.system(size: 12)).italic().foregroundStyle(theme.textMuted)
            }
            if !images.isEmpty || model.uploading > 0 {
                KitFlowLayout(spacing: 8) {
                    ForEach(images) { a in
                        KitAttachmentThumb(path: a.url, name: NoteAttachmentRules.displayName(forURL: a.url)) { Task { await model.open(a) } }
                            .contextMenu { menu(for: a) }
                    }
                    ForEach(0..<model.uploading, id: \.self) { _ in
                        ProgressView().controlSize(.small).frame(width: 64, height: 64)
                            .background(theme.elevated, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
            }
            ForEach(files) { a in
                KitAttachmentFileRow(name: NoteAttachmentRules.displayName(forURL: a.url), mimeType: a.mimeType) { Task { await model.open(a) } }
                    .contextMenu { menu(for: a) }
            }
            HStack(spacing: 8) {
                Button("Attach") { model.showFilePicker = true }
                    .buttonStyle(KitButtonStyle(.secondary, small: true))
                    .help("Attach an image, PDF or text file, or drag files onto the note")
                Text("or drop files on the note").font(.system(size: 11)).foregroundStyle(theme.textMuted)
            }
        }
        .fileImporter(isPresented: $model.showFilePicker, allowedContentTypes: [.image, .pdf, .plainText], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { Task { await model.attach(urls) } }
        }
        .kitConfirm("Remove this attachment?", item: $model.pendingRemoveAttachment,
                    confirmLabel: "Remove", destructive: true) { value in
            Task { await model.confirmRemoveAttachment(value) }
        }
        .sheet(item: $model.viewingAttachment) { a in
            KitImageViewer(path: a.url, name: NoteAttachmentRules.displayName(forURL: a.url)) { model.viewingAttachment = nil }
        }
    }

    @ViewBuilder private func menu(for a: Note.Attachment) -> some View {
        Button("Open") { Task { await model.open(a) } }
        Button("Save As…") { Task { await model.saveAs(a) } }
        Divider()
        Button("Remove", role: .destructive) { model.pendingRemoveAttachment = a }
    }

    // ── Thoughts ────────────────────────────────────────────────────────────

    private var thoughts: some View {
        let all = editor.note?.thoughts ?? []
        return VStack(alignment: .leading, spacing: 8) {
            KitGroupLabel(text: "Thoughts")
            if all.isEmpty { Text("No thoughts yet.").font(.system(size: 12)).italic().foregroundStyle(theme.textMuted) }
            ForEach(all) { t in
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(t.author) · \(Fmt.monthDay(t.createdAt))").font(.system(size: 11)).foregroundStyle(theme.textMuted)
                        Text(t.content).font(.system(size: 13)).foregroundStyle(theme.text300).textSelection(.enabled)
                    }
                    Spacer(minLength: 0)
                    Button("Delete") { model.pendingDeleteThought = t.id }
                        .buttonStyle(KitButtonStyle(.ghost, small: true))
                }
            }
            HStack(spacing: 8) {
                KitTextField(placeholder: "Add a thought", text: $model.newThought, onSubmit: { Task { await model.addThought() } })
                Button("Add") { Task { await model.addThought() } }
                    .buttonStyle(KitButtonStyle(.primary, small: true))
                    .disabled(model.newThought.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .kitConfirm("Delete this thought?", item: $model.pendingDeleteThought,
                    confirmLabel: "Delete", destructive: true) { value in
            Task { await model.confirmDeleteThought(value) }
        }
    }

    private var reviewDate: Binding<Date?> {
        Binding(get: { editor.reviewDate.map { Fmt.localDate($0) } }, set: { editor.reviewDate = $0.map { Fmt.ymd($0) } })
    }
}
