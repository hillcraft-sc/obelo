import SwiftUI

/// What the menu bar can ask of the Calendar screen (View ▸ Previous, Next, Today, Week, Month; Edit ▸ Delete, Edit)
struct CalendarActions {
    let previous: () -> Void
    let next: () -> Void
    let today: () -> Void
    let showWeek: () -> Void
    let showMonth: () -> Void
    let edit: () -> Void
    let delete: () -> Void
}

extension FocusedValues {
    @Entry var calendarActions: CalendarActions?
}

/// Calendar: the week or month grid, and the event on the right while one is open
struct CalendarScreen: View {
    @Environment(AppState.self) private var app
    @Environment(KitToastCenter.self) private var toast
    @Environment(MacRouter.self) private var router
    @Environment(\.theme) private var theme
    @State private var model = Self.makeModel()

    private static func makeModel() -> CalendarScreenModel {
        #if DEBUG
        CalendarScreenModel.make()
        #else
        CalendarScreenModel()
        #endif
    }

    var body: some View {
        Group {
            if model.isPaneOpen {
                KitSplitView(storageKey: "calendar", defaultWidth: 640, minLeading: 460, minTrailing: 320) {
                    CalendarGridPane(model: model)
                } trailing: {
                    EventPane(model: model)
                }
            } else {
                CalendarGridPane(model: model)
            }
        }
        .background(theme.page)
        .task {
            await model.load()
            if let event = router.calendarRequest {
                router.calendarRequest = nil
                await model.store.open(event)
            }
            #if DEBUG
            // Testing: `-calendarMode month`, `-calendarDay 2026-12-03`, `-calendarSelect 3`, `-calendarEdit YES`,
            // `-calendarNew YES`, `-calendarSources none|some`
            let d = UserDefaults.standard
            if d.string(forKey: "calendarMode") == "month" { await model.store.setMode(.month) }
            if let day = d.string(forKey: "calendarDay") { await model.store.show(day: day) }
            let id = d.integer(forKey: "calendarSelect")
            if id > 0 { model.select(id) }
            if d.bool(forKey: "calendarEdit") { model.editSelected() }
            if d.bool(forKey: "calendarNew") { model.newEvent() }
            #endif
        }
        .onChange(of: app.dataVersion) { Task { await model.load() } }
        .onChange(of: router.calendarRequest) { _, event in
            guard let event else { return }
            router.calendarRequest = nil
            Task { await model.store.open(event) }
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
        .onNewItem("calendar") { model.newEvent() }
        .focusedSceneValue(\.calendarActions, CalendarActions(
            previous: { model.previous() }, next: { model.next() }, today: { model.today() },
            showWeek: { model.setMode(.week) }, showMonth: { model.setMode(.month) },
            edit: { if !MacFocus.isEditingText { model.editSelected() } },
            delete: { if !MacFocus.isEditingText { model.requestDeleteSelected() } }))
        .kitConfirm("Delete this event?", item: $model.pendingDelete,
                    confirmLabel: "Delete", destructive: true) { value in
            Task { await model.confirmDelete(value) }
        }
    }
}
