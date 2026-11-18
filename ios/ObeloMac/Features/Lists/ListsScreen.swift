import SwiftUI

/// What the menu bar can ask of the Lists screen (Edit ▸ Delete: the open list, owner only)
struct ListsActions {
    let delete: () -> Void
}

extension FocusedValues {
    @Entry var listsActions: ListsActions?
}

/// Lists: your lists on the left, the selected list's items on the right
struct ListsScreen: View {
    @Environment(AppState.self) private var app
    @Environment(KitToastCenter.self) private var toast
    @Environment(MacRouter.self) private var router
    @Environment(\.theme) private var theme
    @State private var model = Self.makeModel()

    private static func makeModel() -> ListsScreenModel {
        #if DEBUG
        ListsScreenModel.make()
        #else
        ListsScreenModel()
        #endif
    }

    var body: some View {
        KitSplitView(storageKey: "lists", defaultWidth: 380, minLeading: 280, minTrailing: 420) {
            ListsListPane(model: model)
        } trailing: {
            ListDetailPane(model: model)
        }
        .background(theme.page)
        .task {
            await model.load()
            if let id = router.listsRequest {
                router.listsRequest = nil
                await model.select(id)
            }
            #if DEBUG
            // Testing: `-listsSelect 1` opens a list, `-listsNew YES` opens the new form
            let d = UserDefaults.standard
            let id = d.integer(forKey: "listsSelect")
            if id > 0 { await model.select(id) }
            if d.bool(forKey: "listsNew") { await model.newList() }
            #endif
        }
        .onChange(of: app.dataVersion) { Task { await model.load() } }
        .onChange(of: router.listsRequest) { _, id in
            guard let id else { return }
            router.listsRequest = nil
            Task { await model.select(id) }
        }
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
        .onNewItem("lists") { Task { await model.newList() } }
        .onDisappear { Task { await model.leave() } }
        .focusedSceneValue(\.listsActions, ListsActions(delete: {
            if !MacFocus.isEditingText { model.requestDeleteOpenList() }
        }))
        .kitConfirm("Delete this list and all its items?",
                    item: $model.pendingDeleteList,
                    confirmLabel: "Delete", destructive: true) { value in
            Task { await model.confirmDelete(value) }
        }
    }
}
