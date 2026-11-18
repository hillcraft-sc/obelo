import SwiftUI

/// What the menu bar can ask of the Notes screen: Format menu items, New Folder, Toggle Details, Find
struct NotesActions {
    let format: (MarkdownFormat) -> Void
    let newFolder: () -> Void
    let toggleDetails: () -> Void
    let find: () -> Void
}

extension FocusedValues {
    @Entry var notesActions: NotesActions?
}

/// Notes (web: notes/workspace.ejs): the folder tree on the left, the open note in the middle, its details
/// on the right. Step 4a: writing, filing and details; handwriting,
/// attachments, locked notes and thoughts come in 4b.
struct NotesScreen: View {
    @Environment(AppState.self) private var app
    @Environment(MacRouter.self) private var router
    @Environment(KitToastCenter.self) private var toast
    @Environment(\.theme) private var theme
    @State private var model = Self.makeModel()
    @State private var controller = KitMarkdownEditorController()
    @AppStorage("notesDetailsVisible") private var detailsVisible = true
    @AppStorage("notesOpenID") private var lastOpenID = 0

    private static func makeModel() -> NotesScreenModel {
        #if DEBUG
        MacDebug.notesModel()
        #else
        NotesScreenModel()
        #endif
    }

    var body: some View {
        KitSplitView(storageKey: "notes.tree", fixed: .leading, defaultWidth: 250, minLeading: 200, minTrailing: 440) {
            NotesTreePane(model: model)
        } trailing: {
            if detailsVisible {
                KitSplitView(storageKey: "notes.details", fixed: .trailing, defaultWidth: 300, minLeading: 320, minTrailing: 260) {
                    NoteEditorPane(model: model, controller: controller, detailsVisible: $detailsVisible)
                } trailing: {
                    NoteDetailsPane(model: model)
                }
            } else {
                NoteEditorPane(model: model, controller: controller, detailsVisible: $detailsVisible)
            }
        }
        .background(theme.page)
        .task {
            model.store.collapsed = Self.savedCollapsed()
            await model.load()
            if let id = router.notesRequest {
                router.notesRequest = nil
                await model.show(id)
            } else if lastOpenID > 0 {
                await model.open(lastOpenID)
            }
            #if DEBUG
            // Testing: `-notesOpen 3` opens a note, `-notesPreview YES` shows it in Preview
            let d = UserDefaults.standard
            if d.integer(forKey: "notesOpen") > 0 { await model.open(d.integer(forKey: "notesOpen")) }
            if d.bool(forKey: "notesPreview") { model.previewMode = true }
            #endif
        }
        .onChange(of: router.notesRequest) { _, id in
            guard let id else { return }
            router.notesRequest = nil
            Task { await model.show(id) }
        }
        .onChange(of: app.dataVersion) { Task { await model.store.load() } }
        .onChange(of: model.selectedID) { _, id in lastOpenID = id ?? 0 }
        .onChange(of: model.store.collapsed) { _, set in UserDefaults.standard.set(set.sorted(), forKey: "notesCollapsedFolders") }
        .onChange(of: model.store.error) { _, message in
            guard let message else { return }
            toast.show(message, isError: true)
            model.store.error = nil
        }
        .onChange(of: model.message) { _, message in
            guard let message else { return }
            toast.show(message, isError: model.messageIsError)
            model.message = nil
        }
        .onNewItem("notes") { Task { await model.newNote() } }
        .onDisappear { Task { await model.leave() } }
        .focusedSceneValue(\.notesActions, NotesActions(
            format: { if model.editor != nil, !model.previewMode { controller.apply($0) } },
            newFolder: { model.askNewFolder() },
            toggleDetails: { detailsVisible.toggle() },
            find: { model.focusSearch = true }))
        .alert(nameTitle, isPresented: Binding(get: { model.naming != nil }, set: { if !$0 { model.naming = nil } })) {
            TextField("Name", text: $model.nameText)
            Button(nameButton) { Task { await model.submitName() } }
            Button("Cancel", role: .cancel) {}
        }
        .kitConfirm("Delete this note?", item: $model.pendingDeleteNote,
                    confirmLabel: "Delete", destructive: true, message: "This cannot be undone.") { value in
            Task { await model.confirmDeleteNote(value) }
        }
        .kitConfirm("Delete this folder?", item: $model.pendingDeleteFolder,
                    confirmLabel: "Delete", destructive: true, message: "Its notes and subfolders move up one level.") { value in
            Task { await model.confirmDeleteFolder(value) }
        }
    }

    private var nameTitle: String {
        switch model.naming {
        case .newFolder(let parent): parent == nil ? "New folder" : "New subfolder"
        case .rename: "Rename folder"
        case .saveTemplate: "Save as template"
        case nil: ""
        }
    }

    private var nameButton: String {
        switch model.naming {
        case .newFolder: "Create"
        case .rename: "Rename"
        case .saveTemplate: "Save"
        case nil: "OK"
        }
    }

    private static func savedCollapsed() -> Set<Int> {
        Set((UserDefaults.standard.array(forKey: "notesCollapsedFolders") as? [Int]) ?? [])
    }
}
