import SwiftUI

/// One row (web: routines/_row.ejs): select box, square tick box, title, streak, "Day 3/30", frequency
struct MacRoutineRow: View {
    @Environment(\.theme) private var theme
    @Bindable var model: RoutinesScreenModel
    let routine: Routine
    let showFrequency: Bool
    var listFocused: FocusState<Bool>.Binding

    private var selected: Bool { model.rows.contains(routine.id) }
    private var canToggle: Bool { routine.completedToday || routine.dueToday }

    var body: some View {
        KitRow(isSelected: selected, onClick: { command, shift in
            listFocused.wrappedValue = true
            model.click(routine.id, command: command, shift: shift)
        }) { _ in
            HStack(spacing: 10) {
                KitCheckbox(title: "Select \(routine.title)", isOn: Binding(get: { selected }, set: { _ in model.tick(routine.id) }),
                            showsTitle: false)
                    .labelsHidden()
                KitCompleteSquare(done: routine.completedToday, enabled: canToggle) { Task { await model.toggleToday(routine.id) } }
                Text(routine.title)
                    .font(.system(size: 14))
                    .strikethrough(routine.completedToday)
                    .foregroundStyle(routine.completedToday ? theme.textMuted : theme.text200)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if routine.streakCurrent > 0 {
                    Text("🔥 \(routine.streakCurrent)").font(.system(size: 12))
                        .foregroundStyle(routine.completedToday ? theme.amber400 : theme.textMuted).fixedSize()
                        .help("Current streak: \(routine.streakCurrent) days")
                }
                if let days = routine.durationDays, routine.active {
                    Text("Day \(routine.completionCount)/\(days)").font(.system(size: 12)).foregroundStyle(theme.accentText).fixedSize()
                        .help("Day \(routine.completionCount) of \(days)")
                }
                if showFrequency {
                    Text(Fmt.freqLabels[routine.frequency] ?? routine.frequency).font(.system(size: 12)).foregroundStyle(theme.textMuted).fixedSize()
                }
            }
        }
        .contextMenu { menu }
    }

    /// Right-click: acts on the whole selection when this row is part of a multi-selection
    @ViewBuilder private var menu: some View {
        if selected, model.rows.count > 1 {
            Button("Mark Done Today") { Task { await model.completeSelection() } }
            Button(model.store.view == "archived" ? "Restore" : "Archive") {
                Task { await model.bulk(model.store.view == "archived" ? "restore" : "archive") }
            }
            Divider()
            Button("Delete \(model.rows.count) Routines…", role: .destructive) { model.requestDeleteSelection() }
        } else {
            Button(routine.completedToday ? "Undo Done Today" : canToggle ? "Mark Done Today" : "Not Scheduled Today") {
                Task { await model.toggleToday(routine.id) }
            }
            .disabled(!canToggle)
            Button(routine.active ? "Archive" : "Restore") { Task { await model.toggleArchived(routine.id) } }
            Divider()
            Button("Delete…", role: .destructive) { model.requestDelete([routine.id]) }
        }
    }
}
