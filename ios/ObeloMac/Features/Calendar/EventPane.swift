import SwiftUI

/// The right pane: the event (web: calendar/show.ejs), or the form for a new or an edited event
/// (web: new.ejs, edit.ejs)
struct EventPane: View {
    @Environment(\.theme) private var theme
    @Bindable var model: CalendarScreenModel

    var body: some View {
        Group {
            if model.pane != .none {
                EventEditForm(model: model)
            } else if let e = model.viewing {
                EventDetails(model: model, event: e)
            } else {
                KitEmptyState(message: "Select an event.")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.page)
    }
}

private struct EventDetails: View {
    @Environment(AppState.self) private var app
    @Environment(\.theme) private var theme
    @Bindable var model: CalendarScreenModel
    let event: CalendarEvent

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Rectangle().fill(Color(hex: event.color)).frame(height: 6)
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 8) {
                        Text(event.title).font(.system(size: 22, weight: .semibold)).foregroundStyle(theme.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        KitIconButton(systemImage: "xmark", label: "Close") { model.close() }
                    }
                    line("calendar") {
                        let day = Text(CalendarStore.longDate(event.day)).foregroundStyle(theme.text300)
                        let time = Text("  " + CalendarStore.timeText(event, hour12: app.hour12)).foregroundStyle(theme.textMuted)
                        Text("\(day)\(time)")
                    }
                    if let loc = event.location, !loc.isEmpty {
                        line("mappin.and.ellipse") { Text(loc).foregroundStyle(theme.text300) }
                    }
                    if let name = event.calendarName {
                        HStack(spacing: 8) {
                            KitColorDot(hex: event.color)
                            Text(name).font(.system(size: 12)).foregroundStyle(theme.text300)
                            if event.editable { KitBadge(text: "created in Obelo", tone: .info) }
                        }
                    }
                    let notes = CalendarStore.cleanNotes(event.description)
                    if !notes.isEmpty {
                        KitDivider()
                        Text(notes).font(.system(size: 14)).foregroundStyle(theme.textMuted).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if CalendarStore.isWebLink(event.url) {
                        KitLinkButton(title: "Open link ↗", size: 14) { model.open(event) }
                    }
                    if event.editable {
                        KitDivider()
                        HStack(spacing: 8) {
                            Button("Edit event") { model.edit(event.id) }.buttonStyle(KitButtonStyle(.secondary))
                            Button("Delete event") { model.requestDelete(event.id) }.buttonStyle(KitButtonStyle(.danger))
                        }
                    }
                }
                .padding(24)
            }
            .frame(maxWidth: KitWidth.form, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollEdgeEffectHidden(true, for: .top)
    }

    private func line(_ icon: String, @ViewBuilder _ text: () -> some View) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).font(.system(size: 13)).foregroundStyle(theme.textMuted).frame(width: 16).padding(.top, 2).accessibilityHidden(true)
            text().font(.system(size: 14)).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct EventEditForm: View {
    @Environment(\.theme) private var theme
    @Bindable var model: CalendarScreenModel

    private var store: CalendarStore { model.store }
    private var submit: () -> Void { { Task { await model.save() } } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(model.isNew ? "New Event" : "Edit Event")
                    .font(.system(size: 24, weight: .bold)).foregroundStyle(theme.textPrimary)
                if let e = model.formError { KitBanner(kind: .error, text: e) }
                KitFieldLabel(text: "Title *") {
                    KitTextField(placeholder: "Event title", text: $model.draft.title, onSubmit: submit,
                                 focusRequest: $model.focusTitle, onCancel: { model.cancel() })
                }
                KitFieldLabel(text: "Date *") {
                    KitDateField(value: Binding(get: { Fmt.localDate(model.draft.date) }, set: { model.draft.date = Fmt.ymd($0) }), label: "Date")
                }
                KitCheckbox(title: "All day", isOn: $model.draft.allDay)
                if !model.draft.allDay {
                    HStack(spacing: 12) {
                        KitFieldLabel(text: "Start time") {
                            KitTimeField(value: Binding(get: { Fmt.date(fromHHMM: model.draft.startTime) }, set: { model.draft.startTime = Fmt.hhmm(from: $0) }), label: "Start time")
                        }
                        KitFieldLabel(text: "End time") {
                            KitTimeField(value: Binding(get: { Fmt.date(fromHHMM: model.draft.endTime) }, set: { model.draft.endTime = Fmt.hhmm(from: $0) }), label: "End time")
                        }
                    }
                }
                KitFieldLabel(text: "Location") {
                    KitTextField(placeholder: "Optional", text: $model.draft.location, onSubmit: submit, onCancel: { model.cancel() })
                }
                KitFieldLabel(text: "Notes") {
                    KitTextArea(placeholder: "Optional", text: $model.draft.description, minHeight: 72)
                }
                if model.isNew {
                    KitDivider()
                    KitFieldLabel(text: "Calendar") {
                        KitSelect(options: store.choices.map { (value: $0.value, label: $0.label) },
                                  selection: $model.draft.calendarTarget, label: "Calendar")
                    }
                }
                HStack(spacing: 8) {
                    Button(model.isNew ? "Create event" : "Update event", action: submit)
                        .buttonStyle(KitButtonStyle(.primary))
                        .disabled(!model.isNew && !model.isDirty)
                    Button("Cancel") { model.cancel() }.buttonStyle(KitButtonStyle(.secondary))
                }
                .padding(.top, 4)
            }
            .padding(24)
            .frame(maxWidth: KitWidth.form, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollEdgeEffectHidden(true, for: .top)
    }
}
