import SwiftUI

/// The right pane: the selected reminder, edited in place and saved automatically, or the "New reminder"
/// form (web: reminders/show.ejs and form.ejs)
struct ReminderDetailPane: View {
    @Environment(\.theme) private var theme
    @Bindable var model: RemindersScreenModel

    var body: some View {
        Group {
            if model.newDraft != nil {
                NewReminderForm(model: model)
            } else if model.rows.count > 1 {
                KitEmptyState(message: "\(model.rows.count) reminders selected")
            } else if let session = model.session, let reminder = model.store.open, session.reminderId == reminder.id {
                ReminderEditor(model: model, session: session, reminder: reminder).id(reminder.id)
            } else {
                KitEmptyState(message: "Select a reminder.")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.page)
    }
}

/// The fields both the editor and the new form show: title, due date and time, Notify me, priority, repeat,
/// notes, tags
private struct ReminderFields: View {
    @Environment(\.theme) private var theme
    @Binding var draft: ReminderDraft
    let suggestions: [String]
    @Binding var focusTitle: Bool
    var onTitleSubmit: () -> Void
    var onTitleCancel: () -> Void
    var onNotesLeave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            KitCard { mainCard }
            KitCard {
                KitCardHeader(title: "Notes")
                KitTextArea(placeholder: "Optional notes…", text: $draft.notes, minHeight: 96,
                            onFocusChange: { focused in if !focused { onNotesLeave() } })
                    .padding(16)
            }
            KitCard {
                KitCardHeader(title: "Tags")
                KitTagPicker(tags: $draft.tags, suggestions: suggestions).padding(16)
            }
            .zIndex(1)
        }
    }

    private var mainCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            KitTitleField(placeholder: "Reminder title", text: $draft.title, onSubmit: onTitleSubmit,
                          onCancel: onTitleCancel, focusRequest: $focusTitle)
            Grid(alignment: .topLeading, horizontalSpacing: 16, verticalSpacing: 14) {
                GridRow {
                    KitFieldLabel(text: "Due date") {
                        KitOptionalDateField(components: .date, value: dueDate, label: "Due date", emptyLabel: "Set date")
                    }
                    KitFieldLabel(text: "Due time") {
                        KitOptionalDateField(components: .hourAndMinute, value: dueTime, label: "Due time", emptyLabel: "Set time")
                    }
                }
                GridRow {
                    KitFieldLabel(text: "Notify me") {
                        KitSelect(options: Fmt.reminderOffsets.map { (value: $0.0, label: $0.1) },
                                  selection: $draft.reminderOffset, label: "Notify me")
                    }
                    KitFieldLabel(text: "Priority") {
                        KitSelect(options: RemindersStore.priorities.map { (value: $0, label: Fmt.priorityLabel($0)) },
                                  selection: $draft.priority, label: "Priority")
                    }
                }
            }
            RepeatEditor(recurring: $draft.recurring, rule: $draft.recurRule)
        }
        .padding(16)
    }

    private var dueDate: Binding<Date?> {
        Binding(get: { draft.dueDate.isEmpty ? nil : Fmt.localDate(draft.dueDate) },
                set: { draft.dueDate = $0.map { Fmt.ymd($0) } ?? "" })
    }

    private var dueTime: Binding<Date?> {
        Binding(get: { draft.dueTime.isEmpty ? nil : Fmt.date(fromHHMM: draft.dueTime) },
                set: { draft.dueTime = $0.map { Fmt.hhmm(from: $0) } ?? "" })
    }
}

// ── An existing reminder ────────────────────────────────────────────────────

private struct ReminderEditor: View {
    @Environment(\.theme) private var theme
    @Environment(AppState.self) private var app
    @Bindable var model: RemindersScreenModel
    @Bindable var session: ReminderEditSession
    let reminder: ReminderItem

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                savedLine
                summary
                ReminderFields(draft: $session.draft, suggestions: model.store.allTags, focusTitle: $model.focusTitle,
                               onTitleSubmit: { Task { await session.flush() } },
                               onTitleCancel: { session.revert(\.title) },
                               onNotesLeave: { Task { await session.flush() } })
                actions
                footer
            }
            .padding(24)
            .frame(maxWidth: KitWidth.form + 64)
            .frame(maxWidth: .infinity)
        }
        .scrollEdgeEffectHidden(true, for: .top)
        .onChange(of: session.draft.tags) { Task { await session.flush() } }
        .onChange(of: session.draft.priority) { Task { await session.flush() } }
        .onChange(of: session.draft.dueDate) { Task { await session.flush() } }
        .onChange(of: session.draft.dueTime) { Task { await session.flush() } }
        .onChange(of: session.draft.reminderOffset) { Task { await session.flush() } }
        .onChange(of: session.draft.recurring) { Task { await session.flush() } }
        .onChange(of: session.draft.recurRule) { Task { await session.flush() } }
    }

    private var savedLine: some View {
        HStack {
            Spacer()
            switch session.state {
            case .saving: Text("Saving…").foregroundStyle(theme.textMuted)
            case .saved: Text("Saved").foregroundStyle(theme.textMuted)
            case .failed:
                Button("Couldn't save. Try again") { Task { await session.flush() } }
                    .buttonStyle(.plain).foregroundStyle(theme.red400)
            case .idle: Text(" ")
            }
        }
        .font(.system(size: 12))
        .accessibilityElement(children: .combine)
    }

    /// The web page's summary line, read-only: the full due date and time, Overdue, and when it will notify
    private var summary: some View {
        let hour12 = app.me?.hour12 ?? true
        return VStack(alignment: .leading, spacing: 4) {
            if let date = reminder.dueDate {
                HStack(spacing: 8) {
                    Text(Fmt.longDay(date) + (reminder.dueTime.map { " at " + Fmt.time($0, hour12: hour12) } ?? ""))
                        .foregroundStyle(reminder.dueState == "overdue" ? theme.red400 : reminder.dueState == "today" ? theme.green400 : theme.text400)
                    if reminder.dueState == "overdue" {
                        Text("OVERDUE").font(.system(size: 11, weight: .bold)).tracking(0.6).foregroundStyle(theme.red400)
                    }
                }
                .font(.system(size: 14))
            }
            if let at = reminder.reminderAt {
                Text("Notify: " + Fmt.monthDay(at) + ", " + Fmt.clock(at, hour12: hour12, tz: model.timeZone))
                    .font(.system(size: 12)).foregroundStyle(theme.textMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                if reminder.completed {
                    Button("Restore") { Task { await model.restore(reminder.id) } }.buttonStyle(KitButtonStyle(.secondary)).fixedSize()
                    if let done = reminder.completedAt {
                        Text("Completed \(Fmt.monthDay(done))").font(.system(size: 14)).foregroundStyle(theme.green400).fixedSize()
                    }
                } else {
                    Button("Mark complete") { Task { await session.flush(); await model.complete(reminder.id) } }
                        .buttonStyle(KitButtonStyle(.primary)).fixedSize()
                }
                Spacer(minLength: 8)
                Button("Delete") { model.requestDelete([reminder.id]) }.buttonStyle(KitButtonStyle(.danger)).fixedSize()
            }
            if !reminder.completed {
                HStack(spacing: 8) {
                    Text("Snooze:").font(.system(size: 14)).foregroundStyle(theme.textMuted)
                    ForEach(RemindersStore.snoozes, id: \.0) { duration, label in
                        Button(label) { Task { await model.snooze(reminder.id, duration) } }
                            .buttonStyle(KitButtonStyle(.secondary, small: true)).fixedSize()
                    }
                }
            }
        }
    }

    private var footer: some View {
        Text("Created \(Fmt.monthDayYear(reminder.createdAt))")
            .font(.system(size: 12)).foregroundStyle(theme.textMuted)
    }
}

// ── A reminder being made ───────────────────────────────────────────────────

private struct NewReminderForm: View {
    @Environment(\.theme) private var theme
    @Bindable var model: RemindersScreenModel

    var body: some View {
        let draft = Binding(get: { model.newDraft ?? ReminderDraft() }, set: { model.newDraft = $0 })
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("New reminder").font(.system(size: 20, weight: .bold)).foregroundStyle(theme.textPrimary)
                ReminderFields(draft: draft, suggestions: model.store.allTags, focusTitle: $model.focusTitle,
                               onTitleSubmit: { Task { await model.addNew() } },
                               onTitleCancel: {}, onNotesLeave: {})
                HStack(spacing: 10) {
                    Button("Add reminder") { Task { await model.addNew() } }
                        .buttonStyle(KitButtonStyle(.primary))
                        .disabled(!draft.wrappedValue.isComplete)
                    Button("Cancel") { model.cancelNew() }
                        .buttonStyle(KitButtonStyle(.ghost))
                        .keyboardShortcut(.cancelAction)
                    Spacer()
                }
            }
            .padding(24)
            .frame(maxWidth: KitWidth.form + 64)
            .frame(maxWidth: .infinity)
        }
        .scrollEdgeEffectHidden(true, for: .top)
    }
}
