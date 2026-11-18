import SwiftUI

/// What the menu bar can ask of the Routines screen (File ▸ Mark Complete, Delete)
struct RoutinesActions {
    let complete: () -> Void
    let delete: () -> Void
}

extension FocusedValues {
    @Entry var routinesActions: RoutinesActions?
}

/// Routines: the list on the left, the selected routine on the right
struct RoutinesScreen: View {
    @Environment(AppState.self) private var app
    @Environment(KitToastCenter.self) private var toast
    @Environment(MacRouter.self) private var router
    @Environment(\.theme) private var theme
    @State private var model = Self.makeModel()

    private static func makeModel() -> RoutinesScreenModel {
        #if DEBUG
        RoutinesScreenModel.make()
        #else
        RoutinesScreenModel()
        #endif
    }

    var body: some View {
        KitSplitView(storageKey: "routines", defaultWidth: 520, minLeading: 340, minTrailing: 340) {
            RoutinesListPane(model: model)
        } trailing: {
            RoutineDetailPane(model: model)
        }
        .background(theme.page)
        .task {
            #if DEBUG
            if let view = UserDefaults.standard.string(forKey: "routinesView") { model.store.view = view }
            #endif
            await model.load()
            if let id = router.routinesRequest {
                router.routinesRequest = nil
                await model.show(routine: id)
            }
            #if DEBUG
            // Testing: `-routinesSelect 1,2` selects rows, `-routinesNew YES` opens the new form
            let d = UserDefaults.standard
            if let ids = d.string(forKey: "routinesSelect") {
                for id in ids.split(separator: ",").compactMap({ Int($0) }) { model.click(id, command: true, shift: false) }
            }
            if d.bool(forKey: "routinesNew") { await model.newRoutine() }
            #endif
        }
        .onChange(of: app.dataVersion) { Task { await model.load() } }
        .onChange(of: router.routinesRequest) { _, id in
            guard let id else { return }
            router.routinesRequest = nil
            Task { await model.show(routine: id) }
        }
        .onChange(of: model.store.open?.routine.id) { model.syncOpen() }
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
        .onNewItem("routines") { Task { await model.newRoutine() } }
        .onDisappear { Task { await model.leave() } }
        .focusedSceneValue(\.routinesActions, RoutinesActions(
            complete: { if !MacFocus.isEditingText { Task { await model.completeSelection() } } },
            delete: { if !MacFocus.isEditingText { model.requestDeleteSelection() } }))
        .kitConfirm(model.deleteTitle, item: $model.pendingDelete,
                    confirmLabel: "Delete", destructive: true) { value in
            Task { await model.confirmDelete(value) }
        }
    }
}
