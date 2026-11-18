import SwiftUI

/// The right pane: the selected task, edited in place and saved automatically (web: tasks/show.ejs and form.ejs)
struct TaskDetailPane: View {
    @Environment(\.theme) private var theme
    @Bindable var model: TasksScreenModel

    var body: some View {
        Group {
            if model.rows.count > 1 {
                KitEmptyState(message: "\(model.rows.count) tasks selected")
            } else if let session = model.session, let task = model.store.open, session.taskId == task.id {
                TaskEditor(model: model, session: session, task: task)
                    .id(task.id)
            } else {
                KitEmptyState(message: "Select a task.")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.page)
    }
}

private struct TaskEditor: View {
    @Environment(\.theme) private var theme
    @Environment(AppState.self) private var app
    @Bindable var model: TasksScreenModel
    @Bindable var session: TaskEditSession
    let task: TaskItem
    @State private var editingNotes = false
    @State private var focusNotes = false
    @State private var newSubtask = ""
    @State private var focusSubtask = false

    private var store: TasksStore { model.store }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                savedLine
                KitCard { mainCard }
                notesCard
                KitCard {
                    KitCardHeader(title: "Tags")
                    KitTagPicker(tags: $session.draft.tags, suggestions: store.allTags).padding(16)
                }
                .zIndex(1)
                subtasksCard
                actions
                footer
            }
            .padding(24)
            .frame(maxWidth: KitWidth.form + 64)
            .frame(maxWidth: .infinity)
        }
        .scrollEdgeEffectHidden(true, for: .top)
        .onChange(of: session.draft.tags) { Task { await session.flush() } }
        .onChange(of: session.draft.status) { Task { await session.flush() } }
        .onChange(of: session.draft.priority) { Task { await session.flush() } }
        .onChange(of: session.draft.dueDate) { Task { await session.flush() } }
        .onChange(of: session.draft.dueTime) { Task { await session.flush() } }
        .onChange(of: session.draft.recurring) { Task { await session.flush() } }
        .onChange(of: session.draft.recurRule) { Task { await session.flush() } }
    }

    // ── Saved line ──────────────────────────────────────────────────────────

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

    // ── Title, status, priority, due, repeat ────────────────────────────────

    private var mainCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            KitTitleField(placeholder: "Title", text: $session.draft.title,
                          onSubmit: { Task { await session.flush() } },
                          onCancel: { session.revert(\.title) },
                          focusRequest: $model.focusTitle)
            Grid(alignment: .topLeading, horizontalSpacing: 16, verticalSpacing: 14) {
                GridRow {
                    KitFieldLabel(text: "Status") {
                        KitSelect(options: TasksStore.statuses.map { (value: $0, label: TasksStore.statusLabels[$0] ?? $0) },
                                  selection: $session.draft.status, label: "Status")
                    }
                    KitFieldLabel(text: "Priority") {
                        KitSelect(options: TasksStore.priorities.map { (value: $0, label: TasksStore.priorityLabels[$0] ?? $0) },
                                  selection: $session.draft.priority, label: "Priority")
                    }
                }
                GridRow {
                    KitFieldLabel(text: "Due date") {
                        KitOptionalDateField(components: .date, value: dueDate, label: "Due date", emptyLabel: "Set date")
                    }
                    KitFieldLabel(text: "Time") {
                        KitOptionalDateField(components: .hourAndMinute, value: dueTime, label: "Due time", emptyLabel: "Set time")
                    }
                }
            }
            RepeatEditor(recurring: $session.draft.recurring, rule: $session.draft.recurRule)
        }
        .padding(16)
    }

    private var dueDate: Binding<Date?> {
        Binding(get: { session.draft.dueDate.map { Fmt.localDate($0) } },
                set: { session.draft.dueDate = $0.map { Fmt.ymd($0) } })
    }

    private var dueTime: Binding<Date?> {
        Binding(get: { session.draft.dueTime.map { Fmt.date(fromHHMM: $0) } },
                set: { session.draft.dueTime = $0.map { Fmt.hhmm(from: $0) } })
    }

    // ── Notes ───────────────────────────────────────────────────────────────

    private var notesCard: some View {
        KitCard {
            KitCardHeader(title: "Notes") {
                if !editingNotes, !session.draft.notes.isEmpty {
                    Button("Edit") { editingNotes = true; focusNotes = true }
                        .buttonStyle(KitButtonStyle(.ghost, small: true))
                        .help("Edit the notes")
                }
            }
            Group {
                if editingNotes || session.draft.notes.isEmpty {
                    KitTextArea(placeholder: "Notes", text: $session.draft.notes, minHeight: 96,
                                onFocusChange: { focused in
                                    if !focused { editingNotes = false; Task { await session.flush() } }
                                }, focusRequest: $focusNotes)
                } else {
                    // The shared Markdown renderer (the same one the iPhone and iPad use): headings, lists,
                    // checklists, quotes, code. Not selectable, so a click opens the editor.
                    MarkdownView(text: session.draft.notes, selectable: false)
                        .contentShape(Rectangle())
                        .onTapGesture { editingNotes = true; focusNotes = true }
                        .help("Click to edit")
                        .accessibilityHint("Click to edit")
                }
            }
            .padding(16)
        }
    }

    // ── Subtasks ────────────────────────────────────────────────────────────

    private var subtasksCard: some View {
        let subs = task.subtasks ?? []
        return KitCard {
            KitCardHeader(title: "Subtasks", detail: subs.isEmpty ? nil : "\(subs.filter(\.done).count)/\(subs.count) done")
            VStack(spacing: 0) {
                ForEach(subs) { sub in
                    SubtaskRow(sub: sub,
                               toggle: { Task { await store.toggleSubtask(sub.id) } },
                               delete: { Task { await store.deleteSubtask(sub.id) } })
                    KitDivider()
                }
                HStack(spacing: 8) {
                    KitTextField(placeholder: "Add a subtask…", text: $newSubtask,
                                 onSubmit: { addSubtask() }, focusRequest: $focusSubtask)
                    Button("Add") { addSubtask() }.buttonStyle(KitButtonStyle(.secondary))
                }
                .padding(16)
            }
        }
    }

    private func addSubtask() {
        let text = newSubtask
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        newSubtask = ""
        Task { await store.addSubtask(text); focusSubtask = true }
    }

    // ── Buttons and footer ──────────────────────────────────────────────────

    private var actions: some View {
        HStack(spacing: 10) {
            if task.isDone {
                Button("Restore to inbox") { Task { await model.restore(task.id) } }.buttonStyle(KitButtonStyle(.secondary))
            } else {
                Button("Mark complete") { Task { await session.flush(); await model.complete(task.id) } }
                    .buttonStyle(KitButtonStyle(.primary))
            }
            Spacer()
            Button("Delete") { model.requestDelete([task.id]) }.buttonStyle(KitButtonStyle(.danger))
        }
    }

    private var footer: some View {
        Text("Created \(Fmt.monthDayYear(task.createdAt))"
             + (task.completedAt.map { " · Completed \(Fmt.monthDayYear($0))" } ?? ""))
            .font(.system(size: 12)).foregroundStyle(theme.textMuted)
    }
}

private struct SubtaskRow: View {
    @Environment(\.theme) private var theme
    @State private var hovering = false
    let sub: TaskItem.Subtask
    let toggle: () -> Void
    let delete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            KitCheckbox(title: sub.title, isOn: Binding(get: { sub.done }, set: { _ in toggle() }), showsTitle: false)
                .labelsHidden()
            Text(sub.title).font(.system(size: 14)).strikethrough(sub.done)
                .foregroundStyle(sub.done ? theme.textMuted : theme.text200)
                .frame(maxWidth: .infinity, alignment: .leading)
            KitIconButton(systemImage: "trash", label: "Delete subtask", destructive: true, action: delete)
                .opacity(hovering ? 1 : 0)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .accessibilityElement(children: .contain)
    }
}
