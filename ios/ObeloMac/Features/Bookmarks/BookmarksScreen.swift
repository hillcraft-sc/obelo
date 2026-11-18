import SwiftUI

/// What the menu bar can ask of the Bookmarks screen (Edit ▸ Delete, Find, Edit Bookmark)
struct BookmarksActions {
    let delete: () -> Void
    let find: () -> Void
    let edit: () -> Void
}

extension FocusedValues {
    @Entry var bookmarksActions: BookmarksActions?
}

/// Bookmarks: the table on the left, the selected bookmark (or the new one) on the right
struct BookmarksScreen: View {
    @Environment(AppState.self) private var app
    @Environment(KitToastCenter.self) private var toast
    @Environment(MacRouter.self) private var router
    @Environment(\.theme) private var theme
    @State private var model = Self.makeModel()

    private static func makeModel() -> BookmarksScreenModel {
        #if DEBUG
        BookmarksScreenModel.make()
        #else
        BookmarksScreenModel()
        #endif
    }

    var body: some View {
        KitSplitView(storageKey: "bookmarks", defaultWidth: 640, minLeading: 420, minTrailing: 320) {
            BookmarksListPane(model: model)
        } trailing: {
            BookmarkDetailPane(model: model)
        }
        .background(theme.page)
        .task {
            await model.load()
            if let id = router.bookmarksRequest {
                router.bookmarksRequest = nil
                model.click(id, command: false, shift: false)
            }
            #if DEBUG
            // Testing: `-bookmarksSelect 1,2` selects rows, `-bookmarksNew YES` opens the new form,
            // `-bookmarksTag work` filters, `-bookmarksSort title` sorts, `-bookmarksSearch text` filters
            let d = UserDefaults.standard
            if let tag = d.string(forKey: "bookmarksTag") { model.store.activeTag = tag }
            if let q = d.string(forKey: "bookmarksSearch") { model.store.search = q }
            if let key = d.string(forKey: "bookmarksSort"), let k = BookmarkSortKey(rawValue: key) { model.store.sort(by: k) }
            if let ids = d.string(forKey: "bookmarksSelect") {
                for id in ids.split(separator: ",").compactMap({ Int($0) }) { model.click(id, command: true, shift: false) }
            }
            if d.bool(forKey: "bookmarksNew") { model.newBookmark() }
            if d.bool(forKey: "bookmarksShare"), let id = model.store.selection.single { model.openShare(id) }
            #endif
        }
        .onChange(of: app.dataVersion) { Task { await model.load() } }
        .onChange(of: router.bookmarksRequest) { _, id in
            guard let id else { return }
            router.bookmarksRequest = nil
            model.click(id, command: false, shift: false)
        }
        .onChange(of: model.store.selection) { model.syncPane() }
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
        .onNewItem("bookmarks") { model.newBookmark() }
        .focusedSceneValue(\.bookmarksActions, BookmarksActions(
            delete: { if !MacFocus.isEditingText { model.requestDelete() } },
            find: { model.focusFilter = true },
            edit: { model.edit() }))
        .kitConfirm(model.deleteTitle, item: $model.pendingDelete,
                    confirmLabel: "Delete", destructive: true) { value in
            Task { await model.confirmDelete(value) }
        }
    }
}
