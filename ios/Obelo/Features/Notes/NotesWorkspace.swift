import SwiftUI

// The notes workspace for wide screens (Mac, and iPad at full width), as on the web
// (views/notes/workspace.ejs): the folder tree on the left with pinned notes above it, the open
// note in the middle ready to edit, and its details on the right (NoteDetailView's side panel).
// iPhone keeps NotesView, where the tree is a drawer and a note fills the screen.

struct NotesWorkspace: View {
    @Environment(AppState.self) private var app
    @Environment(Toast.self) private var toast
    @Environment(\.theme) private var theme

    @State private var notes: [NoteSummary] = []
    @State private var folders: [NoteFolder] = []
    @State private var loaded = false
    @State private var error: String?
    @State private var search = ""
    @State private var creating = false
    @State private var templates = NoteTemplatesStore()
    @State private var showFolders = false
    @State private var moving: NoteSummary?
    /// The note made with New note, deleted again if it's left blank
    @State private var newID: Int?
    @AppStorage("workspaceNote") private var selectedRaw = 0
    /// Collapsed folder ids, "3,7"
    @AppStorage("workspaceCollapsed") private var collapsedRaw = ""

    private var selected: Int? { selectedRaw == 0 ? nil : selectedRaw }
    private var collapsed: Set<Int> { Set(collapsedRaw.split(separator: ",").compactMap { Int($0) }) }

    var body: some View {
        HStack(spacing: 0) {
            // Pane colours run up under the window toolbar, so the panes reach the top of the window
            tree
                .frame(width: 260)
                .background(theme.surface.ignoresSafeArea(edges: .top))
            Rectangle().fill(theme.border1).frame(width: 1).ignoresSafeArea(edges: .top)
            Group {
                if let id = selected {
                    NoteDetailView(id: id, isNew: id == newID, inline: true) { close(id) }
                        .id(id)
                } else {
                    VStack {
                        EmptyRow(text: notes.isEmpty && loaded ? "No notes yet." : "Choose a note, or start a new one.",
                                 action: EmptyAction(label: "New note") { newNote() })
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(theme.page)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .background(theme.page.ignoresSafeArea())
        .task(id: app.dataVersion) { await load() }
        .task { await templates.load() }
        .onNewItem("notes") { newNote() }
        .sheet(isPresented: $showFolders) {
            FoldersSheet(folders: $folders, scope: .constant(.all), counts: counts, total: notes.count)
                .presentationDetents([.medium, .large])
                .environment(\.theme, theme)
        }
        .sheet(item: $moving) { note in
            MoveToFolderSheet(folders: folders, current: note.folderId) { move(note.id, to: $0) }
                .presentationDetents([.medium, .large])
                .environment(\.theme, theme)
        }
    }

    // ── Tree pane ────────────────────────────────────────────────────────────

    private var tree: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text("Notes").font(.system(size: 17, weight: .bold)).foregroundStyle(theme.textPrimary)
                    Spacer()
                    smallButton("folder", label: "Folders") { showFolders = true }
                    NoteTemplateMenu(templates: templates.templates, blank: { newNote() }, start: { newNote(template: $0) }) {
                        Image(systemName: "square.and.pencil").font(.system(size: 13, weight: .medium)).foregroundStyle(theme.onAccent)
                            .frame(width: 30, height: 28)
                            .background(theme.accent, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                    .disabled(creating)
                    .accessibilityLabel("New note")
                    .accessibilityHint("Press and hold for templates")
                    .help("New note (press and hold for templates)")
                }
                ThemedField(placeholder: "Search notes", text: $search) { Task { await load() } }
            }
            .padding(12)
            .overlay(alignment: .bottom) { RowDivider() }
            .onChange(of: search) { _, new in if new.isEmpty { Task { await load() } } }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    if let error { Banner(kind: .error, text: error).padding(8) }
                    if !search.isEmpty {
                        if notes.isEmpty && loaded {
                            Text("No notes match this search.").font(.system(size: 13)).foregroundStyle(theme.textMuted)
                                .frame(maxWidth: .infinity).padding(.vertical, 30)
                        }
                        ForEach(notes) { noteRow($0, depth: 0) }
                    } else {
                        let pinned = notes.filter(\.pinned)
                        if !pinned.isEmpty {
                            sectionLabel("Pinned", color: theme.amber400)
                            ForEach(pinned) { noteRow($0, depth: 0) }
                            RowDivider().padding(.vertical, 6)
                        }
                        ForEach(rows) { row in
                            switch row.kind {
                            case .folder(let f): folderRow(f, depth: row.depth)
                            case .note(let n): noteRow(n, depth: row.depth)
                            }
                        }
                        if loaded && notes.isEmpty && folders.isEmpty {
                            Text("No notes yet.").font(.system(size: 13)).foregroundStyle(theme.textMuted)
                                .frame(maxWidth: .infinity).padding(.vertical, 30)
                        }
                        topLevelDrop
                    }
                }
                .padding(.vertical, 6)
            }
            .refreshable { await load() }
        }
    }

    private func smallButton(_ icon: String, label: String, accent: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 13, weight: .medium))
                .foregroundStyle(accent ? theme.onAccent : theme.text300)
                .frame(width: 30, height: 28)
                .background(accent ? theme.accent : theme.elevated, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(label)
        .help(label)
    }

    private func sectionLabel(_ title: String, color: Color) -> some View {
        Text(title.uppercased()).font(.system(size: 11, weight: .semibold)).tracking(0.6)
            .foregroundStyle(color.opacity(0.85))
            .padding(.horizontal, 12).padding(.top, 4).padding(.bottom, 2)
    }

    /// Folders in tree order, each followed by its notes; a collapsed folder hides what's inside.
    /// Top-level notes come after the folders, as on the web.
    private struct Row: Identifiable {
        enum Kind { case folder(NoteFolder), note(NoteSummary) }
        let kind: Kind
        let depth: Int
        var id: String {
            switch kind {
            case .folder(let f): "f\(f.id)"
            case .note(let n): "n\(n.id)"
            }
        }
    }

    private var rows: [Row] {
        let byFolder = Dictionary(grouping: notes, by: { $0.folderId ?? 0 })
        var out: [Row] = []
        var hiddenUnder: Int? = nil  // depth of a collapsed folder whose contents are being skipped
        for (folder, depth) in NoteFolders.tree(folders) {
            if let h = hiddenUnder { if depth > h { continue } else { hiddenUnder = nil } }
            out.append(Row(kind: .folder(folder), depth: depth))
            if collapsed.contains(folder.id) { hiddenUnder = depth; continue }
            for n in byFolder[folder.id] ?? [] { out.append(Row(kind: .note(n), depth: depth + 1)) }
        }
        for n in byFolder[0] ?? [] { out.append(Row(kind: .note(n), depth: 0)) }
        return out
    }

    private var counts: [Int: Int] { Dictionary(grouping: notes, by: { $0.folderId ?? 0 }).mapValues(\.count) }

    private func folderRow(_ f: NoteFolder, depth: Int) -> some View {
        let isCollapsed = collapsed.contains(f.id)
        return Button { toggle(f.id) } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).foregroundStyle(theme.textMuted)
                    .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                    .frame(width: 12)
                Image(systemName: isCollapsed ? "folder" : "folder.fill").font(.system(size: 12)).foregroundStyle(theme.textMuted)
                Text(f.name).font(.system(size: 13, weight: .medium)).foregroundStyle(theme.text200).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.leading, 8 + CGFloat(depth) * 14).padding(.trailing, 10).padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .dropDestination(for: String.self) { items, _ in
            guard let id = items.compactMap(NoteFolders.noteID(fromDrag:)).first else { return false }
            move(id, to: f.id)
            return true
        }
        .contextMenu {
            Button("New note here", systemImage: "square.and.pencil") { newNote(in: f.id) }
            Button("Manage folders…", systemImage: "folder.badge.gearshape") { showFolders = true }
        }
        .accessibilityLabel("\(f.name) folder, \(isCollapsed ? "collapsed" : "expanded")")
    }

    private func noteRow(_ n: NoteSummary, depth: Int) -> some View {
        let active = n.id == selected
        return Button { select(n.id) } label: {
            HStack(spacing: 6) {
                if n.pinned { Circle().fill(theme.amber400).frame(width: 5, height: 5) }
                if n.hasDrawing { Image(systemName: "pencil.tip").font(.system(size: 10)).foregroundStyle(theme.textMuted) }
                Text(n.title.isEmpty ? "Untitled" : n.title)
                    .font(.system(size: 13))
                    .foregroundStyle(active ? theme.textPrimary : theme.text400)
                    .lineLimit(1)
                if n.locked { Image(systemName: "lock.fill").font(.system(size: 9)).foregroundStyle(theme.textMuted) }
                Spacer(minLength: 0)
            }
            .padding(.leading, 8 + CGFloat(depth) * 14 + 18).padding(.trailing, 10).padding(.vertical, 5)
            .background(active ? theme.accent.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .draggable(NoteFolders.dragText(n.id))
        .contextMenu {
            Button("Move to…", systemImage: "folder") { moving = n }
            Button(n.pinned ? "Unpin" : "Pin", systemImage: n.pinned ? "pin.slash" : "pin") { togglePin(n) }
            Button("Delete", systemImage: "trash", role: .destructive) { delete(n) }
        }
    }

    /// Dropping a note here moves it out of its folder
    private var topLevelDrop: some View {
        Text("Top level").font(.system(size: 11)).foregroundStyle(theme.textMuted)
            .frame(maxWidth: .infinity).padding(.vertical, 8)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(theme.border1, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            .padding(.horizontal, 10).padding(.top, 12).padding(.bottom, 8)
            .dropDestination(for: String.self) { items, _ in
                guard let id = items.compactMap(NoteFolders.noteID(fromDrag:)).first else { return false }
                move(id, to: nil)
                return true
            }
            .accessibilityHidden(true)
    }

    // ── Actions ──────────────────────────────────────────────────────────────

    private func load() async {
        do {
            async let list: NotesView.Response = APIClient.shared.get("/notes", query: ["type": "all", "search": search.isEmpty ? nil : search])
            async let tree = try? NoteFolders.load()
            let (r, f) = try await (list, tree)
            if let f { folders = f }
            withAnimation(.easeOut(duration: 0.15)) { notes = r.notes }
            loaded = true
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    private func select(_ id: Int) {
        guard id != selected else { return }
        selectedRaw = id
    }

    /// The open note was deleted
    private func close(_ id: Int) {
        if selected == id { selectedRaw = 0 }
        withAnimation { notes.removeAll { $0.id == id } }
    }

    private func toggle(_ folder: Int) {
        var set = collapsed
        if set.contains(folder) { set.remove(folder) } else { set.insert(folder) }
        withAnimation(.easeOut(duration: 0.15)) { collapsedRaw = set.sorted().map(String.init).joined(separator: ",") }
    }

    /// An untitled note, opened at once (in a folder when made from that folder's menu)
    private func newNote(in folder: Int? = nil, template: NoteTemplate? = nil) {
        guard !creating else { return }
        creating = true
        Task {
            defer { creating = false }
            do {
                let r: NotesView.Created = try await APIClient.shared.post("/notes", [
                    "title": template?.startTitle ?? "Untitled", "type": template?.type ?? "note", "content": template?.content ?? "",
                    "folderId": folder.map { $0 as Any } ?? NSNull(),
                ])
                newID = r.note.id
                selectedRaw = r.note.id
                await load()
            } catch { toast.show(error.localizedDescription, error: true) }
        }
    }

    private func move(_ noteID: Int, to folder: Int?) {
        guard let i = notes.firstIndex(where: { $0.id == noteID }), notes[i].folderId != folder else { return }
        withAnimation(.easeOut(duration: 0.15)) { notes[i].folderId = folder }
        toast.run {
            try await NoteFolders.move(note: noteID, to: folder)
            toast.show("Moved to \(NoteFolders.path(folder, in: folders))")
            app.dataChanged()
        }
    }

    private func togglePin(_ n: NoteSummary) {
        toast.run {
            try await APIClient.shared.post("/notes/\(n.id)/pin")
            toast.show(n.pinned ? "Unpinned" : "Pinned")
            app.dataChanged()
        }
    }

    private func delete(_ n: NoteSummary) {
        close(n.id)
        toast.run {
            try await APIClient.shared.delete("/notes/\(n.id)")
            toast.show("Note deleted")
            app.dataChanged()
        }
    }
}
