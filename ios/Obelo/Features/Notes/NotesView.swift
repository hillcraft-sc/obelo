import SwiftUI

// Notes — the web's notes workspace (views/notes/workspace.ejs), laid out for iPhone: the folder tree
// is a drawer from the header, a note opens full screen ready to edit, and everything that isn't the
// text itself sits in a Details sheet.

private let typeColor: [String: Color] = [
    "note": StatusPalette.tailwind.blue500, "journal": Color(hex: "#10b981"), "quote": Color(hex: "#8b5cf6"),
]

struct NotesView: View {
    @Environment(AppState.self) private var app
    @Environment(Toast.self) private var toast
    @Environment(\.theme) private var theme

    nonisolated struct Response: Decodable { let notes: [NoteSummary]; let tags: [String]; let slippingCount: Int }
    struct Created: Decodable { let note: Note }

    @State private var type = "all"
    @State private var tag: String?
    @State private var search = ""
    @State private var data: Response?
    @State private var notes: [NoteSummary] = []
    @State private var folders: [NoteFolder] = []
    @AppStorage("notesScope") private var scopeRaw = "all"
    @State private var error: String?
    @State private var showFolders = false
    @State private var moving: NoteSummary?
    @State private var creating = false
    @State private var templates = NoteTemplatesStore()
    /// A note made with New note, opened straight away in the editor
    @State private var opened: Int?

    private var scope: NoteScope { NoteScope(raw: scopeRaw) }
    private var scopeBinding: Binding<NoteScope> { Binding(get: { scope }, set: { scopeRaw = $0.raw }) }
    private var filtering: Bool { type != "all" || tag != nil || !search.isEmpty }

    private var shown: [NoteSummary] {
        switch scope {
        case .all: notes
        case .folder(let id): notes.filter { $0.folderId == id }
        }
    }

    /// Notes per folder id, 0 = the top level
    private var counts: [Int: Int] { Dictionary(grouping: notes, by: { $0.folderId ?? 0 }).mapValues(\.count) }

    var body: some View {
        Page(refresh: load) {
            PageHeader(title: "Notes", subtitle: "Notes, journal entries and quotes.", pageName: true) {
                HStack(spacing: 8) {
                    Button { showFolders = true } label: {
                        Image(systemName: "folder").font(.system(size: 15)).foregroundStyle(theme.text400)
                            .frame(width: 38, height: 36)
                            .background(theme.elevated, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(theme.border2, lineWidth: 1))
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityLabel("Folders")
                    NoteTemplateMenu(templates: templates.templates, blank: { newNote() }, start: { newNote(template: $0) }) {
                        HStack(spacing: 6) {
                            if creating { ProgressView().tint(theme.onAccent).controlSize(.small) }
                            else { Image(systemName: "plus").font(.system(size: 13, weight: .semibold)) }
                            Text("New note").font(.system(size: 14, weight: .medium))
                        }
                        .foregroundStyle(theme.onAccent)
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(theme.accent, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .disabled(creating)
                    .accessibilityLabel("New note")
                    .accessibilityHint("Press and hold for templates")
                }
            }
            scopeBar
            SectionTabs(tabs: [
                SectionTab(key: "all", label: "All"), SectionTab(key: "note", label: "Notes"),
                SectionTab(key: "journal", label: "Journal"), SectionTab(key: "quote", label: "Quotes"),
                SectionTab(key: "flagged", label: "Flagged"),
                SectionTab(key: "slipping", label: "Slipping", badge: data?.slippingCount, warn: true),
            ], selection: $type)
            ThemedField(placeholder: "Search notes...", text: $search) { Task { await load() } }
                .submitLabel(.search)
            TagFilter(tags: data?.tags ?? [], selected: $tag)
            if let error { Banner(kind: .error, text: error) }
            if data == nil {
                ProgressView().frame(maxWidth: .infinity).padding(40)
            } else {
                if !filtering { folderRows }
                if shown.isEmpty {
                    Card { EmptyRow(text: emptyText, action: emptyAction) }
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(shown) { note in noteRow(note) }
                    }
                }
            }
        }
        .task(id: "\(type)|\(tag ?? "")|\(app.dataVersion)") {
            await load()
            #if DEBUG
            // Simulator testing: `-notesSheet folders|move|new` opens the folder drawer, Move to… for the first note, or a New note
            switch UserDefaults.standard.string(forKey: "notesSheet") {
            case "folders": showFolders = true
            case "move": moving = shown.first
            case "new": if opened == nil { newNote() }
            default: break
            }
            #endif
        }
        .onChange(of: search) { _, new in if new.isEmpty { Task { await load() } } }
        .onNewItem("notes") { newNote() }
        .task { await templates.load() }
        .navigationDestination(item: $opened) { id in NoteDetailView(id: id, isNew: true) }
        .sheet(isPresented: $showFolders) {
            FoldersSheet(folders: $folders, scope: scopeBinding, counts: counts, total: notes.count)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .environment(\.theme, theme)
        }
        .sheet(item: $moving) { note in
            MoveToFolderSheet(folders: folders, current: note.folderId) { move(note.id, to: $0) }
                .presentationDetents([.medium, .large])
                .environment(\.theme, theme)
        }
    }

    // ── Where you are ─────────────────────────────────────────────────────────

    private var scopeTitle: String {
        switch scope {
        case .all: "All notes"
        case .folder(let id): NoteFolders.path(id, in: folders)
        }
    }

    /// One level up: a folder's parent, the top level's "All notes"
    private var parentScope: NoteScope? {
        switch scope {
        case .all: nil
        case .folder(nil): .all
        case .folder(let id?): .folder(folders.first { $0.id == id }?.parentId)
        }
    }

    private var scopeBar: some View {
        HStack(spacing: 6) {
            if let parentScope {
                Button { withAnimation(.easeOut(duration: 0.15)) { scopeRaw = parentScope.raw } } label: {
                    Image(systemName: "chevron.left").font(.system(size: 14, weight: .semibold)).foregroundStyle(theme.text400)
                        .frame(width: 30, height: 30).background(theme.elevated, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Up one level")
            }
            Button { showFolders = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: scope == .all ? "tray.full" : "folder").font(.system(size: 14)).foregroundStyle(theme.textMuted)
                    Text(scopeTitle).font(.system(size: 15, weight: .semibold)).foregroundStyle(theme.text200).lineLimit(1)
                    Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold)).foregroundStyle(theme.textMuted)
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows your folders")
            Spacer()
        }
    }

    /// The open folder's subfolders, plus a row to go (or move a note) up one level
    @ViewBuilder private var folderRows: some View {
        let children: [NoteFolder] = switch scope {
        case .all: NoteFolders.children(of: nil, in: folders)
        case .folder(let id): NoteFolders.children(of: id, in: folders)
        }
        if case .folder(let id?) = scope, let up = parentScope {
            let parent = folders.first { $0.id == id }?.parentId
            FolderRow(title: up == .all ? "Top level" : NoteFolders.path(parent, in: folders), icon: "arrowshape.turn.up.left",
                      open: { scopeRaw = (parent == nil ? NoteScope.folder(nil) : up).raw },
                      drop: { move($0, to: parent) })
        }
        if !children.isEmpty {
            VStack(spacing: 6) {
                ForEach(children) { f in
                    FolderRow(title: f.name, count: NoteFolders.subtree(f.id, in: folders).reduce(0) { $0 + (counts[$1] ?? 0) },
                              open: { withAnimation(.easeOut(duration: 0.15)) { scopeRaw = NoteScope.folder(f.id).raw } },
                              drop: { move($0, to: f.id) })
                }
            }
        }
    }

    private var emptyText: String {
        if filtering { return type == "slipping" && tag == nil && search.isEmpty
            ? "Nothing slipping. Every note was touched in the last 30 days." : "No notes match this filter." }
        switch scope {
        case .all: return "No notes yet."
        case .folder(nil): return "No notes at the top level."
        case .folder: return "No notes in this folder yet."
        }
    }

    private var emptyAction: EmptyAction? {
        if type == "slipping" && tag == nil && search.isEmpty { return nil }
        if filtering { return EmptyAction(label: "Clear filter") { type = "all"; tag = nil; search = "" } }
        return EmptyAction(label: "New note") { newNote() }
    }

    private func noteRow(_ note: NoteSummary) -> some View {
        SwipeRow(onComplete: { togglePin(note) }, onDelete: { delete(note) },
                 completeLabel: note.pinned ? "Unpin" : "Pin", completeIcon: "pin",
                 completeColor: Color(hex: "#b45309"), transparent: true) {
            NoteCard(note: note, slipping: type == "slipping",
                     folder: scope == .all && note.folderId != nil ? NoteFolders.path(note.folderId, in: folders) : nil)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        // Long-press and drag onto a folder row to move the note there
        .draggable(NoteFolders.dragText(note.id))
        .contextMenu {
            Button { moving = note } label: { Label("Move to…", systemImage: "folder") }
            Button { togglePin(note) } label: { Label(note.pinned ? "Unpin" : "Pin", systemImage: note.pinned ? "pin.slash" : "pin") }
            Button(role: .destructive) { delete(note) } label: { Label("Delete", systemImage: "trash") }
        }
    }

    // ── Actions ───────────────────────────────────────────────────────────────

    private func load() async {
        do {
            async let list: Response = APIClient.shared.get("/notes", query: ["type": type, "tag": tag, "search": search.isEmpty ? nil : search])
            // A server without folders (before 3.32) still shows notes
            async let tree = try? NoteFolders.load()
            let (r, f) = try await (list, tree)
            data = r
            if let f { folders = f }
            // The open folder was deleted elsewhere
            if case .folder(let id?) = scope, f != nil, !folders.contains(where: { $0.id == id }) { scopeRaw = NoteScope.all.raw }
            withAnimation(.easeOut(duration: 0.15)) { notes = r.notes }
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    /// Creates an untitled note in the open folder and opens it, as the web workspace's New note does
    /// A blank note, or one started from a template (its type, starting title and text)
    private func newNote(template: NoteTemplate? = nil) {
        creating = true
        let folder: Int? = if case .folder(let id) = scope { id } else { nil }
        let noteType = ["note", "journal", "quote"].contains(type) ? type : "note"
        Task {
            defer { creating = false }
            do {
                let r: Created = try await APIClient.shared.post("/notes", [
                    "title": template?.startTitle ?? "Untitled", "type": template?.type ?? noteType, "content": template?.content ?? "",
                    "folderId": folder.map { $0 as Any } ?? NSNull(),
                ])
                opened = r.note.id
            } catch { toast.show(error.localizedDescription, error: true) }
        }
    }

    private func move(_ noteID: Int, to folder: Int?) {
        guard let i = notes.firstIndex(where: { $0.id == noteID }), notes[i].folderId != folder else { return }
        withAnimation(.easeOut(duration: 0.15)) { notes[i].folderId = folder }
        toast.run {
            try await NoteFolders.move(note: noteID, to: folder)
            toast.show("Moved to \(NoteFolders.path(folder, in: folders))")
            await load()
        }
    }

    private func togglePin(_ note: NoteSummary) {
        toast.run {
            try await APIClient.shared.post("/notes/\(note.id)/pin")
            toast.show(note.pinned ? "Unpinned" : "Pinned")
            await load()
        }
    }

    private func delete(_ note: NoteSummary) {
        withAnimation { notes.removeAll { $0.id == note.id } }
        toast.run {
            try await APIClient.shared.delete("/notes/\(note.id)")
            toast.show("Note deleted")
            app.dataChanged()
        }
    }
}

struct NoteCard: View {
    @Environment(\.theme) private var theme
    let note: NoteSummary
    var slipping = false
    /// The note's folder, shown when the list mixes folders
    var folder: String? = nil

    private var preview: String {
        note.preview.replacing(/<[^>]+>/, with: "").replacing(/[#*`\[\]_>!]/, with: "")
            .replacing(/\s+/, with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationLink(value: Route.note(note.id)) {
            HStack(spacing: 0) {
                Rectangle().fill(typeColor[note.type] ?? theme.h3).frame(width: 4)
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            if note.pinned { Image(systemName: "pin.fill").font(.system(size: 11)).foregroundStyle(theme.amber400) }
                            if note.locked { Image(systemName: "lock.fill").font(.system(size: 11)).foregroundStyle(theme.amber500) }
                            if note.private { Image(systemName: "eye.slash").font(.system(size: 11)).foregroundStyle(theme.textMuted) }
                            if note.hasDrawing { Image(systemName: "pencil.tip").font(.system(size: 11)).foregroundStyle(theme.accentText) }
                            if note.flaggedForReview { Image(systemName: "flag.fill").font(.system(size: 10)).foregroundStyle(theme.red400) }
                            Text(note.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(theme.text100).lineLimit(1)
                        }
                        if note.locked {
                            Text("Locked").font(.system(size: 12)).italic().foregroundStyle(Color(hex: "#b45309"))
                        } else if note.hasDrawing {
                            Text("Handwritten note").font(.system(size: 12)).italic().foregroundStyle(theme.accentText.opacity(0.7))
                        } else if !preview.isEmpty {
                            Text(String(preview.prefix(180))).font(.system(size: 12)).foregroundStyle(theme.textMuted)
                                .lineLimit(2).lineSpacing(2).multilineTextAlignment(.leading)
                        }
                        if folder != nil || !note.tags.isEmpty {
                            FlowLayout(spacing: 4) {
                                if let folder {
                                    Label(folder, systemImage: "folder").font(.system(size: 11)).foregroundStyle(theme.textMuted)
                                        .labelStyle(.titleAndIcon).padding(.trailing, 4)
                                }
                                ForEach(note.tags, id: \.self) { TagPill(tag: $0) }
                            }
                            .padding(.top, 2)
                        }
                    }
                    Spacer(minLength: 0)
                    if slipping {
                        Badge(text: "\(Int(Date.now.timeIntervalSince(note.updatedAt) / 86400)) days ago",
                              fg: theme.amber500, bg: theme.amber950, border: theme.amber900)
                    } else {
                        Text(Fmt.monthDay(note.updatedAt)).font(.system(size: 10)).foregroundStyle(theme.textMuted)
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 14)
            }
            .background(theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.border1, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// ── Editing ───────────────────────────────────────────────────────────────────

/// An open note, ready to edit. A locked note asks for the PIN first.
struct NoteDetailView: View {
    @Environment(AppState.self) private var app
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @State private var editor: NoteEditor
    /// In the notes workspace (Mac, iPad): Details sits beside the note when there's room
    private let inline: Bool
    /// The workspace's "close": called when the note is deleted, in place of going back
    private let onClose: (() -> Void)?
    @AppStorage("noteDetailsPanel") private var panelOpen = true
    @State private var width: CGFloat = 0
    @State private var preview = false
    @State private var showDetails = false
    @State private var showDrawing = false
    @State private var confirmText = false
    /// The text editor's selection, so the Markdown toolbar formats what's selected (as on the web)
    @State private var selection: TextSelection?
    /// Drawing in place (Mac, iPad): the doc being drawn and the pen
    @State private var inlineDoc: DrawingDoc?
    @State private var penColor = DrawingRenderer.colors[0]
    @State private var penSize: Double = 3
    @State private var erasing = false
    @State private var confirmClear = false
    @State private var pin = ""
    @State private var pinError: String?
    @FocusState private var focus: Field?

    enum Field { case title, body }

    init(id: Int, isNew: Bool = false, inline: Bool = false, onClose: (() -> Void)? = nil) {
        _editor = State(initialValue: NoteEditor(id: id, isNew: isNew))
        self.inline = inline
        self.onClose = onClose
    }

    /// Wide enough for the details panel beside the editor (like the web's xl breakpoint)
    private var roomForPanel: Bool { inline && width >= 700 }
    private var showsPanel: Bool { roomForPanel && panelOpen && editor.note != nil && !editor.isLockedShut }

    private func openDetails() {
        if roomForPanel { withAnimation(.easeOut(duration: 0.15)) { panelOpen.toggle() } } else { showDetails = true }
    }

    var body: some View {
        HStack(spacing: 0) {
            Loadable(value: editor.note, error: editor.error, retry: editor.load) { note in
                if editor.isLockedShut {
                    Page { Card(padding: 20) { unlockForm } }
                } else {
                    editorBody(note)
                }
            }
            if showsPanel {
                Rectangle().fill(theme.border1).frame(width: 1).ignoresSafeArea(edges: .top)
                NoteDetailsSheet(editor: editor, embedded: true)
                    .frame(width: 320)
                    .background(theme.surface.ignoresSafeArea(edges: .top))
                    .transition(.move(edge: .trailing))
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .themedNavBar(theme)
        .toolbar {
            // In the workspace the status and Details sit in the note's own header, as on the web
            if !inline {
                ToolbarItem(placement: .principal) {
                    Text(editor.status).font(.system(size: 12)).foregroundStyle(theme.textMuted).lineLimit(1)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { openDetails() } label: { Image(systemName: "info.circle") }
                        .accessibilityLabel("Details")
                        .disabled(editor.note == nil || editor.isLockedShut)
                }
            }
        }
        .confirmationDialog("Switch to text?", isPresented: $confirmText, titleVisibility: .visible) {
            Button("Remove drawing", role: .destructive) { editor.drawMode = false; inlineDoc = nil }
        } message: { Text("The drawing is removed when the note saves.") }
        .confirmationDialog("Clear the whole drawing?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear", role: .destructive) { inlineDocBinding.wrappedValue.strokes = [] }
        }
        .task {
            guard editor.note == nil else { return }
            await editor.load()
            if editor.isNew { focus = .title }
            #if DEBUG
            // Simulator testing: `-noteAppend "text"` types into the note (autosave), `-noteDetails YES` opens
            // Details, `-notePreview YES` opens Preview
            let d = UserDefaults.standard
            if let text = d.string(forKey: "noteAppend") { editor.content += text }
            if d.bool(forKey: "noteDetails") { showDetails = true }
            if d.bool(forKey: "notePreview") { preview = true }
            #endif
        }
        .onChange(of: editor.snapshot) { editor.changed() }
        .onChange(of: editor.deleted) { _, gone in
            guard gone else { return }
            app.dataChanged()
            if let onClose { onClose() } else { dismiss() }
        }
        .onChange(of: showDrawing) { _, open in editor.coverOpen = open }
        .onChange(of: scenePhase) { _, phase in if phase != .active { Task { await editor.flush() } } }
        .onDisappear(perform: leave)
        // Left while blank (for example by switching tabs), so it was deleted
        .onAppear { if editor.deleted { if let onClose { onClose() } else { dismiss() } } }
        .sheet(isPresented: $showDetails) {
            NoteDetailsSheet(editor: editor)
                .environment(\.theme, theme)
        }
        .fullScreen(isPresented: $showDrawing) {
            DrawingEditor(doc: editor.drawing ?? DrawingDoc(w: 360, h: DrawingDoc.defaultHeight, strokes: [])) { editor.setDrawing($0) }
        }
    }

    /// Text or Draw, as the web editor's toggle. Draw → Text removes a drawing, so it asks first;
    /// a quote can't be handwritten.
    private var drawBinding: Binding<Bool> {
        Binding(get: { editor.drawMode }, set: { draw in
            if !draw && editor.drawing != nil { confirmText = true } else { editor.drawMode = draw }
        })
    }

    private var inlineDocBinding: Binding<DrawingDoc> {
        Binding(get: { inlineDoc ?? editor.drawing ?? DrawingDoc(w: 360, h: DrawingDoc.defaultHeight, strokes: []) },
                set: { inlineDoc = $0; editor.setDrawing($0) })
    }

    private func format(_ f: MarkdownFormat) {
        let (text, range) = MarkdownFormat.apply(f, to: editor.content, selection: characterRange(of: selection, in: editor.content))
        editor.content = text
        selection = selectionAt(range, in: text)
        focus = .body
    }

    /// The web editor's controls: Text/Draw, Write/Preview, then the Markdown toolbar while writing
    private var editorControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                if editor.canDraw {
                    PillSegment(options: [(false, "Text"), (true, "✏\u{FE0E} Draw")], selection: drawBinding)
                }
                if !editor.drawMode {
                    PillSegment(options: [(false, "Write"), (true, "Preview")], selection: Binding(
                        get: { preview }, set: { preview = $0; if $0 { focus = nil } }))
                }
                Spacer(minLength: 0)
            }
            if !editor.drawMode && !preview && editor.type != "quote" {
                MarkdownToolbar { format($0) }
            }
        }
        .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 6)
    }

    private func editorBody(_ note: Note) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                TextField("", text: $editor.title, prompt: Text("Untitled").foregroundStyle(theme.placeholder))
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(theme.textPrimary)
                    .focused($focus, equals: .title)
                    .submitLabel(.next)
                    .onSubmit { if !editor.drawMode { focus = .body } }
                if inline {
                    Text(editor.status).font(.system(size: 12)).foregroundStyle(theme.textMuted).lineLimit(1).fixedSize()
                    Button { openDetails() } label: {
                        Label(showsPanel ? "Hide details" : "Details", systemImage: "sidebar.right")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(showsPanel ? theme.text100 : theme.text400)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(showsPanel ? theme.h2 : theme.elevated, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .fixedSize()
                    .help(showsPanel ? "Hide the details panel" : "Show the details panel")
                }
            }
            .padding(.horizontal, 16).padding(.top, 12)
            metaLine(note)
                .padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 10)
            RowDivider()
            editorControls
            if editor.drawMode {
                if inline { inlineDrawing } else { drawingArea }
            } else if preview {
                ScrollView {
                    Group {
                        if editor.type == "quote" {
                            quotePreview
                        } else if editor.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text("Nothing to preview yet.").font(.system(size: 14)).italic().foregroundStyle(theme.textMuted)
                        } else {
                            // Ticking an item edits the text, and autosave saves it (issue #2)
                            MarkdownView(text: editor.content) { line, done in
                                if let updated = MarkdownView.toggling(editor.content, line: line, done: done) { editor.content = updated }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                }
            } else {
                textArea
                if editor.type == "quote" {
                    HStack(spacing: 10) {
                        ThemedField(placeholder: "Author", text: $editor.author)
                        ThemedField(placeholder: "Source", text: $editor.source)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(theme.page)
    }

    /// Type, folder and the note's flags, under the title
    private func metaLine(_ note: Note) -> some View {
        HStack(spacing: 10) {
            Text((Fmt.noteTypeLabels[editor.type] ?? editor.type).uppercased())
                .font(.system(size: 10, weight: .semibold)).tracking(0.8)
                .foregroundStyle(typeColor[editor.type] ?? theme.textMuted)
            if let path = editor.folderPath {
                Button { openDetails() } label: {
                    Label(path, systemImage: "folder").font(.system(size: 11)).foregroundStyle(theme.textMuted).lineLimit(1)
                }
                .buttonStyle(.plain)
            }
            if editor.pinned { Image(systemName: "pin.fill").font(.system(size: 10)).foregroundStyle(theme.amber400) }
            if note.locked { Image(systemName: "lock.fill").font(.system(size: 10)).foregroundStyle(theme.amber500) }
            if editor.isPrivate { Image(systemName: "eye.slash").font(.system(size: 10)).foregroundStyle(theme.textMuted) }
            if editor.flagged { Image(systemName: "flag.fill").font(.system(size: 10)).foregroundStyle(theme.red400) }
            Spacer()
        }
    }

    /// Drawing right in the note, as on the web: the pen toolbar above the canvas. Saves as you draw.
    private var inlineDrawing: some View {
        VStack(spacing: 0) {
            DrawingToolbar(color: $penColor, size: $penSize, erasing: $erasing, paper: app.drawingPaper,
                           canUndo: !inlineDocBinding.wrappedValue.strokes.isEmpty,
                           undo: { inlineDocBinding.wrappedValue.strokes.removeLast() },
                           clear: { confirmClear = true })
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 8, topTrailingRadius: 8, style: .continuous))
            DrawingSurface(doc: inlineDocBinding, color: penColor, penWidth: penSize, erasing: erasing, paper: app.drawingPaper)
                .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 8, bottomTrailingRadius: 8, style: .continuous))
        }
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(theme.border2, lineWidth: 1))
        .padding(.horizontal, 16).padding(.bottom, 16)
    }

    private var textArea: some View {
        TextEditor(text: $editor.content, selection: $selection)
            .font(.system(size: 15))
            .foregroundStyle(theme.text100)
            .scrollContentBackground(.hidden)
            .focused($focus, equals: .body)
            .padding(.horizontal, 11).padding(.top, 6)
            .overlay(alignment: .topLeading) {
                if editor.content.isEmpty {
                    Text(editor.type == "quote" ? "The quote…" : "Start writing. Markdown works here.")
                        .font(.system(size: 15)).foregroundStyle(theme.placeholder)
                        .padding(.horizontal, 16).padding(.top, 14)
                        .allowsHitTesting(false)
                }
            }
    }

    private var quotePreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("“\(editor.content)”").font(.system(size: 18, design: .serif)).italic().foregroundStyle(theme.text200).lineSpacing(4)
            let by = [editor.author, editor.source].filter { !$0.isEmpty }
            if !by.isEmpty { Text("— " + by.joined(separator: ", ")).font(.system(size: 14)).foregroundStyle(theme.textMuted) }
        }
    }

    private var drawingArea: some View {
        ScrollView {
            Group {
                if let doc = editor.drawing {
                    Button { showDrawing = true } label: {
                        DrawingImage(doc: doc, paper: app.drawingPaper)
                            .overlay(alignment: .topTrailing) {
                                Label("Edit", systemImage: "pencil").font(.system(size: 12, weight: .medium)).foregroundStyle(.white)
                                    .padding(.horizontal, 10).padding(.vertical, 5)
                                    .background(.black.opacity(0.5), in: Capsule()).padding(8)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Handwritten note. Double-tap to edit.")
                } else {
                    Button { showDrawing = true } label: {
                        VStack(spacing: 8) {
                            Image(systemName: "pencil.tip.crop.circle").font(.system(size: 30))
                            Text("Tap to draw").font(.system(size: 14, weight: .medium))
                            Text("Finger or Apple Pencil. Handwritten notes aren't searchable.").font(.system(size: 12)).foregroundStyle(theme.textMuted)
                        }
                        .foregroundStyle(theme.text300)
                        .frame(maxWidth: .infinity).padding(.vertical, 40)
                        .background(Color(cgColor: app.drawingPaper.ground), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.border2, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
    }

    private var unlockForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(editor.note?.title ?? "").font(.system(size: 20, weight: .bold)).foregroundStyle(theme.textPrimary)
            Label("This note is locked. Enter your PIN to open it.", systemImage: "lock.fill")
                .font(.system(size: 14)).foregroundStyle(theme.amber400)
            if let pinError { Text(pinError).font(.system(size: 13)).foregroundStyle(theme.red400) }
            HStack(spacing: 8) {
                SecureField("", text: $pin, prompt: Text("PIN").foregroundStyle(theme.placeholder))
                    .keyboardType(.numberPad)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(theme.elevated, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.border2, lineWidth: 1))
                    .foregroundStyle(theme.text100)
                PrimaryButton(title: "Unlock") { unlock() }
            }
        }
    }

    private func unlock() {
        pinError = nil
        Task {
            do {
                try await editor.unlock(pin: pin)
                pin = ""
            } catch { pinError = error.localizedDescription }
        }
    }

    /// Leaving the note saves it at once. A New note left empty is deleted.
    private func leave() {
        guard !editor.coverOpen, !editor.deleted else { return }
        let editor = editor
        Task {
            if editor.isNew && editor.isBlank && editor.note != nil {
                try? await editor.delete()
            } else {
                await editor.flush()
            }
            app.dataChanged()
        }
    }
}

/// Everything about a note that isn't its text: the web workspace's details panel
struct NoteDetailsSheet: View {
    @Environment(AppState.self) private var app
    @Environment(Toast.self) private var toast
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Bindable var editor: NoteEditor
    /// Shown as the workspace's side panel rather than a sheet
    var embedded = false

    @State private var allTags: [String] = []
    @State private var confirmDelete = false
    @State private var namingTemplate = false
    @State private var templateName = ""
    @State private var thought = ""

    var body: some View {
        if embedded {
            panel
        } else {
            NavigationStack {
                panel
                    .themedNavBar(theme, title: "Details")
                    .keyboardDoneButton()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { dismiss() }.fontWeight(.semibold)
                        }
                    }
            }
            .presentationBackground(theme.page)
        }
    }

    /// Closes the sheet; the side panel stays where it is
    private func close() { if !embedded { dismiss() } }

    /// Keeps this note's type, title and text as a template (the web's "Save as template")
    private func saveAsTemplate() {
        var draft = NoteTemplateDraft()
        draft.label = templateName
        draft.type = NoteTemplatesStore.types.contains(editor.type) ? editor.type : "note"
        draft.title = editor.title
        draft.content = editor.content
        let name = templateName.trimmingCharacters(in: .whitespacesAndNewlines)
        toast.run {
            let store = NoteTemplatesStore()
            await store.load()
            if await store.create(draft) != nil { toast.show("Saved the template \u{201C}\(name)\u{201D}") }
            else { toast.show(store.error ?? "Couldn't save the template", error: true) }
        }
    }

    private var panel: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if embedded {
                        Text("DETAILS").font(.system(size: 12, weight: .semibold)).tracking(0.8).foregroundStyle(theme.text400)
                    }
                    FormSection(label: "Folder") {
                        SelectField(options: [(Int?.none, "Top level")] + NoteFolders.tree(editor.folders).map { (Optional($0.folder.id), $0.folder.path ?? $0.folder.name) },
                                    selection: $editor.folderId)
                    }
                    // The web's type selector (notes/_type-selector.ejs); Text/Draw lives in the editor
                    FormSection(label: "Type") {
                        PillSegment(options: [("note", "Note"), ("journal", "Journal"), ("quote", "Quote")],
                                    selection: typeBinding, small: false)
                    }
                    FormSection(label: "Tags") { TagsField(tags: $editor.tags, suggestions: allTags) }
                    if embedded {
                        // The web panel's checkboxes, in one row
                        FlowLayout(spacing: 14) {
                            checkbox("Pinned", $editor.pinned)
                            checkbox("Private", $editor.isPrivate, help: "Never sent to AI features")
                            checkbox("Flag for review", $editor.flagged)
                        }
                    } else {
                        VStack(spacing: 14) {
                            ToggleRow(title: "Pinned", isOn: $editor.pinned)
                            ToggleRow(title: "Private", subtitle: "Never sent to AI features", isOn: $editor.isPrivate)
                            ToggleRow(title: "Flag for review", isOn: $editor.flagged)
                        }
                    }
                    if editor.flagged { FormSection(label: "Review on") { OptionalDateField(ymd: $editor.reviewDate) } }
                    Text("Changes save on their own.").font(.system(size: 12)).foregroundStyle(theme.textMuted)

                    if let note = editor.note {
                        NoteAttachmentsCard(noteID: editor.id, attachments: Binding(
                            get: { editor.note?.attachments ?? [] },
                            set: { editor.note?.attachments = $0 }
                        ))
                        thoughts(note)
                        HStack {
                            if !note.locked && !editor.drawMode && app.me?.canLockNotes == true {
                                SecondaryButton(title: "Lock", systemImage: "lock") {
                                    toast.run { try await editor.lock(); close() }
                                }
                            }
                            if !note.locked && !editor.drawMode {
                                SecondaryButton(title: "Save as template", systemImage: "doc.badge.plus") {
                                    templateName = editor.title == "Untitled" ? "" : editor.title
                                    namingTemplate = true
                                }
                            }
                            Spacer()
                            SecondaryButton(title: "Delete note", systemImage: "trash", tint: theme.red400) { confirmDelete = true }
                        }
                        Text("Created \(note.createdAt.formatted(date: .abbreviated, time: .shortened)) · Updated \(note.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.system(size: 12)).foregroundStyle(theme.textMuted)
                    }
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.immediately)
            .background(embedded ? theme.surface : theme.page)
            .task {
                if let f = try? await NoteFolders.load() { editor.folders = f }
                struct T: Decodable { let tags: [String] }
                allTags = ((try? await APIClient.shared.get("/tags")) as T?)?.tags ?? []
            }
            .alert("Save as template", isPresented: $namingTemplate) {
                TextField("Template name", text: $templateName)
                Button("Save") { saveAsTemplate() }
                Button("Cancel", role: .cancel) {}
            } message: { Text("Keeps this note's type, title and text as a starting point for new notes.") }
            .confirmationDialog("Delete this note?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    toast.run { try await editor.delete(); close() }
                }
            } message: { Text("This can't be undone.") }
    }

    /// A handwritten note can't become a quote, as on the web
    private var typeBinding: Binding<String> {
        Binding(get: { editor.type }, set: { new in
            if new == "quote" && editor.drawMode { toast.show("Handwritten notes can't be quotes", error: true) } else { editor.type = new }
        })
    }

    private func checkbox(_ title: String, _ isOn: Binding<Bool>, help: String? = nil) -> some View {
        Button { isOn.wrappedValue.toggle() } label: {
            HStack(spacing: 6) {
                Image(systemName: isOn.wrappedValue ? "checkmark.square.fill" : "square")
                    .font(.system(size: 14))
                    .foregroundStyle(isOn.wrappedValue ? theme.accent : theme.textMuted)
                Text(title).font(.system(size: 13)).foregroundStyle(theme.text400)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help ?? title)
        .accessibilityAddTraits(isOn.wrappedValue ? .isSelected : [])
    }

    private func thoughts(_ note: Note) -> some View {
        Card {
            CardHeader(title: "Thoughts", badge: note.thoughts.isEmpty ? nil : "\(note.thoughts.count)")
            ForEach(note.thoughts) { t in
                HStack(alignment: .top, spacing: 12) {
                    Text(String(t.author.prefix(1)).uppercased())
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(theme.accentTextLight)
                        .frame(width: 28, height: 28).background(theme.accentSurface, in: Circle())
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(t.author).font(.system(size: 14, weight: .medium)).foregroundStyle(theme.text300)
                            Text(Fmt.monthDay(t.createdAt)).font(.system(size: 12)).foregroundStyle(theme.textMuted)
                        }
                        Text(t.content).font(.system(size: 14)).foregroundStyle(theme.text400).lineSpacing(3)
                    }
                    Spacer()
                    Button { toast.run { try await editor.deleteThought(t.id) } } label: {
                        Image(systemName: "xmark").font(.system(size: 12)).foregroundStyle(theme.textMuted)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Delete thought")
                }
                .padding(.horizontal, 20).padding(.vertical, 12)
                RowDivider()
            }
            HStack(spacing: 8) {
                ThemedField(placeholder: "Add a thought…", text: $thought, axis: .vertical)
                SecondaryButton(title: "Add") {
                    let text = thought.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { return }
                    thought = ""
                    toast.run { try await editor.addThought(text) }
                }
            }
            .padding(16)
        }
    }
}

/// Loads an auth-gated attachment with the session cookie
struct AttachmentImage: View {
    @Environment(\.theme) private var theme
    let path: String
    @State private var image: PlatformImage?

    var body: some View {
        ZStack {
            theme.elevated
            if let image { Image(platformImage: image).resizable().scaledToFill() } else { ProgressView() }
        }
        .task {
            if let data = try? await APIClient.shared.data(path: path) { image = PlatformImage(data: data) }
        }
    }
}
