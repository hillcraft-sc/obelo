import SwiftUI

/// The left pane (web: the workspace's folder tree): heading and buttons, search, the pinned notes, the tree
struct NotesTreePane: View {
    @Environment(\.theme) private var theme
    @Bindable var model: NotesScreenModel
    @FocusState private var treeFocused: Bool

    private var store: NotesStore { model.store }

    var body: some View {
        VStack(spacing: 0) {
            header
            if !store.isFiltered, !store.pinned.isEmpty { pinnedSection }
            ScrollView {
                LazyVStack(spacing: 1) {
                    if store.isFiltered { results } else { tree }
                }
                .padding(.vertical, 4)
                .focusable()
                .focusEffectDisabled()
                .focused($treeFocused)
                .onKeyPress(.downArrow) { keyAct { Task { await model.step(1) } } }
                .onKeyPress(.upArrow) { keyAct { Task { await model.step(-1) } } }
                .onKeyPress(.delete) { keyAct { model.pendingDeleteNote = model.selectedID } }
                .onKeyPress(.deleteForward) { keyAct { model.pendingDeleteNote = model.selectedID } }
            }
            .scrollEdgeEffectHidden(true, for: .top)
        }
        .background(theme.surface.opacity(0.5))
    }

    /// Runs a tree key unless a text field has the cursor
    private func keyAct(_ action: () -> Void) -> KeyPress.Result {
        guard !MacFocus.isEditingText else { return .ignored }
        action()
        return .handled
    }

    // ── Heading, buttons, search ────────────────────────────────────────────

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("Notes").font(.system(size: 15, weight: .semibold)).foregroundStyle(theme.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 4)
                Button("+ Folder") { model.askNewFolder(in: nil) }
                    .buttonStyle(KitButtonStyle(.secondary, small: true))
                    .help("New folder (⌥⌘N)")
                Menu {
                    Button("Blank note") { Task { await model.newNote() } }
                    if !model.templates.templates.isEmpty { Divider() }
                    ForEach(model.templates.templates) { t in
                        Button(t.label) { Task { await model.newNote(template: t) } }
                    }
                } label: {
                    Text("+ Note")
                } primaryAction: {
                    Task { await model.newNote() }
                }
                .menuStyle(.button)
                .buttonStyle(KitButtonStyle(.primary, small: true))
                .fixedSize()
                .help("New note (⌘N). The arrow offers your templates.")
            }
            KitSearchField(placeholder: "Search notes", text: Binding(get: { store.search }, set: { store.search = $0 }),
                           focusRequest: $model.focusSearch)
                .onChange(of: store.search) { model.searchChanged() }
        }
        .padding(.horizontal, 12).padding(.bottom, 10).padding(.top, 14)
        .overlay(alignment: .bottom) { KitDivider() }
    }

    // ── Pinned ──────────────────────────────────────────────────────────────

    private var pinnedSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("PINNED").font(.system(size: 10, weight: .semibold)).tracking(0.8)
                .foregroundStyle(theme.amber400.opacity(0.85))
                .padding(.horizontal, 14).padding(.top, 8).padding(.bottom, 4)
                .accessibilityAddTraits(.isHeader)
            ScrollView {
                VStack(spacing: 1) { ForEach(store.pinned) { noteRow($0, depth: 0, showPin: false) } }
            }
            .frame(height: min(150, CGFloat(store.pinned.count) * 25 + 2))
            .padding(.bottom, 4)
            KitDivider()
        }
    }

    // ── Search results ──────────────────────────────────────────────────────

    @ViewBuilder private var results: some View {
        if store.notes.isEmpty && store.loaded {
            KitEmptyState(message: "No notes match this filter.")
        }
        ForEach(store.notes) { noteRow($0, depth: 0) }
    }

    // ── The tree ────────────────────────────────────────────────────────────

    @ViewBuilder private var tree: some View {
        if store.rows.isEmpty && store.loaded {
            KitEmptyState(message: "No notes yet.")
        }
        ForEach(store.visibleRows) { row in
            switch row {
            case .folder(let folder, let depth, _): folderRow(folder, depth: depth)
            case .note(let note, let depth, _): noteRow(note, depth: depth)
            }
        }
        topLevelStrip
    }

    private func folderRow(_ folder: NoteFolder, depth: Int) -> some View {
        let id = "f\(folder.id)"
        return KitTreeRow(title: folder.name,
                          kind: .folder(expanded: !store.collapsed.contains(folder.id), hasChildren: store.hasChildren(folder.id)),
                          depth: depth,
                          selected: model.selectedFolder == folder.id && model.selectedID == nil,
                          dropTargeted: model.dropTarget == id,
                          onToggle: { store.toggleCollapsed(folder.id) },
                          onClick: { model.selectedFolder = folder.id; treeFocused = true },
                          onDoubleClick: { store.toggleCollapsed(folder.id) }) { hovering in
            HStack(spacing: 0) {
                KitIconButton(systemImage: "plus", label: "New subfolder") { model.askNewFolder(in: folder.id) }
                KitIconButton(systemImage: "pencil", label: "Rename folder") { model.askRename(folder) }
                KitIconButton(systemImage: "xmark", label: "Delete folder", destructive: true) { model.pendingDeleteFolder = folder.id }
            }
            .opacity(hovering ? 1 : 0)
        }
        .dropDestination(for: String.self) { items, _ in
            drop(items, onto: folder.id)
        } isTargeted: { model.dropTarget = $0 ? id : (model.dropTarget == id ? nil : model.dropTarget) }
        .contextMenu {
            Button("New Note Here") { model.selectedFolder = folder.id; Task { await model.newNote() } }
            Button("New Subfolder…") { model.askNewFolder(in: folder.id) }
            Button("Rename…") { model.askRename(folder) }
            Divider()
            Button("Delete Folder…", role: .destructive) { model.pendingDeleteFolder = folder.id }
        }
    }

    private func noteRow(_ note: NoteSummary, depth: Int, showPin: Bool = true) -> some View {
        KitTreeRow(title: note.title.isEmpty ? "Untitled" : note.title, kind: .note, depth: depth,
                   selected: model.selectedID == note.id, pinned: note.pinned && showPin, locked: note.locked,
                   onClick: {
            model.selectedFolder = note.folderId
            treeFocused = true
            Task { await model.open(note.id) }
        })
        .draggable(NoteFolders.dragText(note.id))
        .contextMenu {
            Button(note.pinned ? "Unpin" : "Pin") { Task { await model.togglePin(note.id) } }
            Menu("Move to") {
                Button("Top Level") { Task { await model.move(note: note.id, to: nil) } }
                ForEach(store.folders.sorted { ($0.path ?? $0.name) < ($1.path ?? $1.name) }) { f in
                    Button(f.path ?? f.name) { Task { await model.move(note: note.id, to: f.id) } }
                }
            }
            Divider()
            Button("Delete…", role: .destructive) { model.pendingDeleteNote = note.id }
        }
    }

    /// Dropping a note here moves it to the top level (web: the "Top level" strip)
    private var topLevelStrip: some View {
        Text("Top level")
            .font(.system(size: 12)).foregroundStyle(theme.textMuted)
            .frame(maxWidth: .infinity).padding(.vertical, 8)
            .background(model.dropTarget == "top" ? theme.accent.opacity(0.25) : .clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(theme.border2, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            .padding(.horizontal, 10).padding(.top, 10).padding(.bottom, 6)
            .dropDestination(for: String.self) { items, _ in
                drop(items, onto: nil)
            } isTargeted: { model.dropTarget = $0 ? "top" : (model.dropTarget == "top" ? nil : model.dropTarget) }
            .help("Drop a note here to take it out of its folder")
    }

    private func drop(_ items: [String], onto folder: Int?) -> Bool {
        guard let id = items.compactMap({ NoteFolders.noteID(fromDrag: $0) }).first else { return false }
        Task { await model.move(note: id, to: folder) }
        return true
    }
}
