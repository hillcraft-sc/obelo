import SwiftUI

/// One row (web: reminders/_row.ejs): select box, complete circle, priority, title, due text, Snooze
struct MacReminderRow: View {
    @Environment(\.theme) private var theme
    @Environment(AppState.self) private var app
    @Bindable var model: RemindersScreenModel
    let reminder: ReminderItem
    var listFocused: FocusState<Bool>.Binding

    private var selected: Bool { model.rows.contains(reminder.id) }

    private var dueColour: Color {
        switch reminder.dueState {
        case "overdue": theme.red400
        case "today": theme.green400
        default: theme.textMuted
        }
    }

    var body: some View {
        KitRow(isSelected: selected, onClick: { command, shift in
            listFocused.wrappedValue = true
            model.click(reminder.id, command: command, shift: shift)
        }) { hovering in
            HStack(spacing: 10) {
                KitCheckbox(title: "Select \(reminder.title)", isOn: Binding(get: { selected }, set: { _ in model.tick(reminder.id) }),
                            showsTitle: false)
                    .labelsHidden()
                KitCompleteCircle(done: reminder.completed) {
                    Task { if reminder.completed { await model.restore(reminder.id) } else { await model.complete(reminder.id) } }
                }
                KitPriorityIcon(priority: reminder.priority)
                HStack(spacing: 4) {
                    Text(reminder.title)
                        .font(.system(size: 14))
                        .strikethrough(reminder.completed)
                        .foregroundStyle(reminder.completed ? theme.textMuted : theme.text200)
                        .lineLimit(1)
                    if reminder.recurring {
                        Text("↻").font(.system(size: 11)).foregroundStyle(theme.textMuted).accessibilityLabel("Repeats")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(Fmt.due(reminder.dueDate, reminder.dueTime, hour12: app.me?.hour12 ?? true))
                    .font(.system(size: 12)).foregroundStyle(dueColour).fixedSize()
                if !reminder.completed {
                    KitActionMenu(title: "Snooze") { snoozeItems(for: [reminder.id]) }
                        .opacity(hovering || selected ? 1 : 0)
                }
            }
        }
        .contextMenu { menu }
    }

    @ViewBuilder private func snoozeItems(for ids: [Int]) -> some View {
        ForEach(RemindersStore.snoozes, id: \.0) { duration, label in
            Button(label == "15 min" ? "15 minutes" : label) {
                Task { for id in ids { await model.snooze(id, duration) } }
            }
        }
    }

    /// Right-click: acts on the whole selection when this row is part of a multi-selection
    @ViewBuilder private var menu: some View {
        if selected, model.rows.count > 1 {
            Button("Mark Complete") { Task { await model.bulk("complete") } }
            Menu("Snooze") { snoozeItems(for: Array(model.rows.selected)) }
            Divider()
            Button("Delete \(model.rows.count) Reminders…", role: .destructive) { model.requestDeleteSelection() }
        } else {
            Button(reminder.completed ? "Restore" : "Mark Complete") {
                Task { if reminder.completed { await model.restore(reminder.id) } else { await model.complete(reminder.id) } }
            }
            if !reminder.completed { Menu("Snooze") { snoozeItems(for: [reminder.id]) } }
            Divider()
            Button("Delete…", role: .destructive) { model.requestDelete([reminder.id]) }
        }
    }
}
