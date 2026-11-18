import SwiftUI

/// One row (web: tasks/_row.ejs): tick box, complete circle, priority, title, due date, tags, status
struct MacTaskRow: View {
    @Environment(\.theme) private var theme
    @Environment(AppState.self) private var app
    @Bindable var model: TasksScreenModel
    let task: TaskItem
    let showTags: Bool
    var listFocused: FocusState<Bool>.Binding

    private var selected: Bool { model.rows.contains(task.id) }

    private var dueColour: Color {
        switch task.dueState {
        case "overdue": theme.red400
        case "today": theme.green400
        default: theme.textMuted
        }
    }

    private var statusTint: Color {
        switch task.status {
        case "today": theme.accentText
        case "in-progress": theme.amber400
        case "done": theme.green400
        case "archived": theme.textMuted
        default: theme.text400
        }
    }

    var body: some View {
        KitRow(isSelected: selected, onClick: { command, shift in
            listFocused.wrappedValue = true
            model.click(task.id, command: command, shift: shift)
        }) { _ in
            HStack(spacing: 10) {
                KitCheckbox(title: "Select \(task.title)", isOn: Binding(get: { selected }, set: { _ in model.tick(task.id) }),
                            showsTitle: false)
                    .labelsHidden()
                KitCompleteCircle(done: task.isDone) {
                    Task { if task.isDone { await model.restore(task.id) } else { await model.complete(task.id) } }
                }
                KitPriorityIcon(priority: task.priority)
                Text(task.title)
                    .font(.system(size: 14))
                    .strikethrough(task.isDone)
                    .foregroundStyle(task.isDone ? theme.textMuted : theme.text200)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if task.dueDate != nil {
                    Text(Fmt.shortDay(task.dueDate)).font(.system(size: 12)).foregroundStyle(dueColour)
                        .fixedSize()
                }
                if showTags {
                    ForEach(task.tags.prefix(2), id: \.self) { KitTagLabel(tag: $0) }
                }
                KitSelect(options: TasksStore.statuses.map { (value: $0, label: TasksStore.statusLabels[$0] ?? $0) },
                          selection: Binding(get: { task.status }, set: { changeStatus($0) }),
                          label: "Status", compact: true, tint: statusTint)
            }
        }
        .contextMenu { menu }
    }

    private func changeStatus(_ status: String) {
        Task { await model.setStatus(task.id, status) }
    }

    /// Right-click: acts on the whole selection when this row is part of a multi-selection
    @ViewBuilder private var menu: some View {
        if selected, model.rows.count > 1 {
            Button("Mark Complete") { Task { await model.bulk("complete") } }
            Menu("Priority") {
                ForEach(["high", "medium", "low", "none"], id: \.self) { p in
                    Button(TasksStore.priorityLabels[p] ?? p) { Task { await model.bulk(p) } }
                }
            }
            Button(model.store.view == "archived" ? "Restore to Inbox" : "Archive") {
                Task { await model.bulk(model.store.view == "archived" ? "restore" : "archive") }
            }
            Divider()
            Button("Delete \(model.rows.count) Tasks…", role: .destructive) { model.requestDeleteSelection() }
        } else {
            Button(task.isDone ? "Restore to Inbox" : "Mark Complete") {
                Task { if task.isDone { await model.restore(task.id) } else { await model.complete(task.id) } }
            }
            Menu("Status") {
                ForEach(TasksStore.statuses, id: \.self) { s in
                    Button(TasksStore.statusLabels[s] ?? s) { Task { await model.setStatus(task.id, s) } }
                }
            }
            Menu("Priority") {
                ForEach(["high", "medium", "low", "none"], id: \.self) { p in
                    Button(TasksStore.priorityLabels[p] ?? p) { Task { await model.setPriority(task.id, p) } }
                }
            }
            if task.status != "archived" {
                Button("Archive") { Task { await model.setStatus(task.id, "archived") } }
            }
            Divider()
            Button("Delete…", role: .destructive) { model.requestDelete([task.id]) }
        }
    }
}
