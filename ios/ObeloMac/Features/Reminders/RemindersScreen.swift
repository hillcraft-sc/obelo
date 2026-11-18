import SwiftUI

/// What the menu bar can ask of the Reminders screen (File ▸ Mark Complete, Delete)
struct RemindersActions {
    let complete: () -> Void
    let delete: () -> Void
}

extension FocusedValues {
    @Entry var remindersActions: RemindersActions?
}

/// Reminders: the list on the left, the selected reminder on the right
struct RemindersScreen: View {
    @Environment(AppState.self) private var app
    @Environment(KitToastCenter.self) private var toast
    @Environment(MacRouter.self) private var router
    @Environment(\.theme) private var theme
    @State private var model = Self.makeModel()

    private static func makeModel() -> RemindersScreenModel {
        #if DEBUG
        RemindersScreenModel.make()
        #else
        RemindersScreenModel()
        #endif
    }

    var body: some View {
        KitSplitView(storageKey: "reminders", defaultWidth: 520, minLeading: 340, minTrailing: 320) {
            RemindersListPane(model: model)
        } trailing: {
            ReminderDetailPane(model: model)
        }
        .background(theme.page)
        .task {
            model.timeZone = TimeZone(identifier: app.me?.user.timezone ?? "") ?? .current
            #if DEBUG
            if let view = UserDefaults.standard.string(forKey: "remindersView") { model.store.view = view }
            #endif
            await model.load()
            if let id = router.remindersRequest {
                router.remindersRequest = nil
                await model.show(reminder: id)
            }
            #if DEBUG
            // Testing: `-remindersSelect 1,2` selects rows, `-remindersNew YES` opens the new form
            let d = UserDefaults.standard
            if let ids = d.string(forKey: "remindersSelect") {
                for id in ids.split(separator: ",").compactMap({ Int($0) }) { model.click(id, command: true, shift: false) }
            }
            if d.bool(forKey: "remindersNew") { await model.newReminder() }
            #endif
        }
        .onChange(of: app.dataVersion) { Task { await model.load() } }
        .onChange(of: router.remindersRequest) { _, id in
            guard let id else { return }
            router.remindersRequest = nil
            Task { await model.show(reminder: id) }
        }
        .onChange(of: model.store.open?.id) { model.syncOpen() }
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
        .onNewItem("reminders") { Task { await model.newReminder() } }
        .onDisappear { Task { await model.leave() } }
        .focusedSceneValue(\.remindersActions, RemindersActions(
            complete: { if !MacFocus.isEditingText { Task { await model.completeSelection() } } },
            delete: { if !MacFocus.isEditingText { model.requestDeleteSelection() } }))
        .kitConfirm(model.deleteTitle, item: $model.pendingDelete,
                    confirmLabel: "Delete", destructive: true) { value in
            Task { await model.confirmDelete(value) }
        }
    }
}
