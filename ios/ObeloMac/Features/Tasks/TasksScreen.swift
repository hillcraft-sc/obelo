import SwiftUI

/// What the menu bar can ask of the Tasks screen (File ▸ Mark Complete, Delete; Edit ▸ Find)
struct TasksActions {
    let complete: () -> Void
    let delete: () -> Void
    let find: () -> Void
}

extension FocusedValues {
    @Entry var tasksActions: TasksActions?
}

/// Tasks: the list on the left, the selected task on the right
struct TasksScreen: View {
    @Environment(AppState.self) private var app
    @Environment(KitToastCenter.self) private var toast
    @Environment(MacRouter.self) private var router
    @Environment(\.theme) private var theme
    @State private var model = Self.makeModel()

    private static func makeModel() -> TasksScreenModel {
        #if DEBUG
        TasksScreenModel.make()
        #else
        TasksScreenModel()
        #endif
    }

    var body: some View {
        KitSplitView(storageKey: "tasks", defaultWidth: 540, minLeading: 340, minTrailing: 320) {
            TasksListPane(model: model)
        } trailing: {
            TaskDetailPane(model: model)
        }
        .background(theme.page)
        .task {
            model.timeZone = TimeZone(identifier: app.me?.user.timezone ?? "") ?? .current
            await model.load()
            if let request = router.tasksRequest {
                router.tasksRequest = nil
                await model.handle(request)
            }
            #if DEBUG
            // Testing: `-tasksSelect 1,2` selects those rows once the list has loaded
            if let ids = UserDefaults.standard.string(forKey: "tasksSelect") {
                for id in ids.split(separator: ",").compactMap({ Int($0) }) { model.click(id, command: true, shift: false) }
            }
            // `-tasksAskDelete YES` opens the delete confirmation for the selected rows
            if UserDefaults.standard.bool(forKey: "tasksAskDelete") { model.requestDeleteSelection() }
            #endif
        }
        .onChange(of: app.dataVersion) { Task { await model.load() } }
        .onChange(of: router.tasksRequest) { _, request in
            guard let request else { return }
            router.tasksRequest = nil
            Task { await model.handle(request) }
        }
        .onChange(of: model.store.open?.id) { model.syncOpen() }
        .onChange(of: model.store.error) { _, message in
            guard let message else { return }
            toast.show(message, isError: true)
            model.store.error = nil
        }
        .onNewItem("tasks") { Task { await model.newTask() } }
        .onDisappear { Task { await model.leave() } }
        .focusedSceneValue(\.tasksActions, TasksActions(
            complete: { if !MacFocus.isEditingText { Task { await model.completeSelection() } } },
            delete: { if !MacFocus.isEditingText { model.requestDeleteSelection() } },
            find: { model.focusSearch = true }))
        .kitConfirm(model.deleteTitle, item: $model.pendingDelete,
                    confirmLabel: "Delete", destructive: true) { value in
            Task { await model.confirmDelete(value) }
        }
    }
}
