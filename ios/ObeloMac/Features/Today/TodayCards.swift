import SwiftUI

// The Today cards (web: dashboard/index.ejs). Each takes the store and calls its actions; a click on a
// row opens the item through the router.

/// The title of a row: plain text that goes a shade brighter under the pointer
private struct TodayRowTitle: View {
    @Environment(\.theme) private var theme
    let text: String
    var struck = false
    var weight: Font.Weight = .regular
    var muted = false

    var body: some View {
        Text(text).font(.system(size: 14, weight: weight)).strikethrough(struck)
            .foregroundStyle(struck || muted ? theme.textMuted : theme.text200)
            .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// "Oct 10 · 5:00 PM", red when overdue, green today, grey otherwise
private struct DueText: View {
    @Environment(\.theme) private var theme
    @Environment(AppState.self) private var app
    let date: String?
    let time: String?
    let state: String?

    var body: some View {
        let text = Fmt.due(date, time, hour12: app.hour12)
        if !text.isEmpty {
            Text(text).font(.system(size: 12))
                .foregroundStyle(state == "overdue" ? theme.red400 : state == "today" ? theme.green400 : theme.textMuted)
                .fixedSize()
        }
    }
}

// ── My Focus ────────────────────────────────────────────────────────────────

struct FocusCard: View {
    @Environment(MacRouter.self) private var router
    @Environment(AppState.self) private var app
    @Environment(\.theme) private var theme
    let store: TodayStore
    let timeZone: TimeZone

    var body: some View {
        KitCard {
            KitCardHeader(title: "My Focus", uppercase: true) {
                KitLinkButton(title: "All tasks →", size: 12, tone: .muted) { router.open(.tasks(view: "all", task: nil)) }
            }
            if store.focusTasks.isEmpty {
                KitCardMessage(text: "No tasks set to \"Today\" status.") {
                    KitLinkButton(title: "Set some focus tasks →") { router.open(.tasks(view: "inbox", task: nil)) }
                }
            } else {
                ForEach(store.focusTasks) { task in
                    KitRow(onClick: { _, _ in router.open(.tasks(view: nil, task: task.id)) }) { _ in
                        HStack(spacing: 12) {
                            KitCompleteCircle(done: false, tint: theme.accentHover) { Task { await store.complete(task: task) } }
                            KitPriorityDot(priority: task.priority, size: 10).frame(width: 12)
                            TodayRowTitle(text: task.title, weight: .medium)
                            if let time = task.dueTime {
                                Text(Fmt.time(time, hour12: app.hour12)).font(.system(size: 12)).foregroundStyle(theme.textMuted).fixedSize()
                            }
                        }
                    }
                    .contextMenu { TaskMenu(store: store, task: task) }
                    if task.id != store.focusTasks.last?.id { KitDivider() }
                }
            }
        }
    }
}

private struct TaskMenu: View {
    @Environment(MacRouter.self) private var router
    let store: TodayStore
    let task: TaskItem

    var body: some View {
        Button("Mark Complete") { Task { await store.complete(task: task) } }
        Button("Open") { router.open(.tasks(view: nil, task: task.id)) }
    }
}

// ── Today's Events ──────────────────────────────────────────────────────────

struct EventsCard: View {
    @Environment(MacRouter.self) private var router
    @Environment(AppState.self) private var app
    @Environment(\.theme) private var theme
    let store: TodayStore
    let timeZone: TimeZone

    var body: some View {
        KitCard {
            KitCardHeader(title: "Today's Events", uppercase: true) {
                KitLinkButton(title: "Calendar →", size: 12, tone: .muted) { router.open(.module("calendar")) }
            }
            if store.events.isEmpty {
                KitCardMessage("No events today.")
            } else {
                ForEach(store.events) { event in
                    KitRow(onClick: { _, _ in router.open(.event(event)) }) { _ in
                        HStack(spacing: 12) {
                            Circle().fill(Color(hex: event.color)).frame(width: 8, height: 8).accessibilityHidden(true)
                            TodayRowTitle(text: event.title)
                            Text(event.allDay ? "All day" : Fmt.clock(event.startAt, hour12: app.hour12, tz: timeZone))
                                .font(.system(size: 12)).foregroundStyle(theme.textMuted).fixedSize()
                        }
                    }
                    .contextMenu { Button("Open") { router.open(.event(event)) } }
                    if event.id != store.events.last?.id { KitDivider() }
                }
            }
        }
    }
}

// ── Due Today & Overdue ─────────────────────────────────────────────────────

struct DueCard: View {
    @Environment(MacRouter.self) private var router
    @Environment(\.theme) private var theme
    let store: TodayStore

    var body: some View {
        KitCard {
            KitCardHeader(title: "Due Today & Overdue", uppercase: true, badge: "\(store.due.count)") {
                HStack(spacing: 12) {
                    KitLinkButton(title: "Tasks →", size: 12, tone: .muted) { router.open(.tasks(view: "today", task: nil)) }
                    KitLinkButton(title: "Reminders →", size: 12, tone: .muted) { router.open(.module("reminders")) }
                }
            }
            ForEach(store.due) { entry in
                if let task = entry.task { taskRow(entry, task) }
                else if let reminder = entry.reminder { reminderRow(entry, reminder) }
                if entry.id != store.due.last?.id { KitDivider() }
            }
        }
    }

    private func taskRow(_ entry: Dashboard.DueEntry, _ task: TaskItem) -> some View {
        KitRow(onClick: { _, _ in router.open(.tasks(view: nil, task: task.id)) }) { _ in
            HStack(spacing: 12) {
                KitCompleteCircle(done: false, tint: entry.overdue ? theme.red500 : nil) { Task { await store.complete(task: task) } }
                KitPriorityDot(priority: task.priority).frame(width: 12)
                TodayRowTitle(text: task.title)
                DueText(date: task.dueDate, time: task.dueTime, state: entry.overdue ? "overdue" : task.dueState)
            }
        }
        .contextMenu { TaskMenu(store: store, task: task) }
    }

    private func reminderRow(_ entry: Dashboard.DueEntry, _ reminder: ReminderItem) -> some View {
        KitRow(onClick: { _, _ in router.open(.reminder(reminder.id)) }) { hovering in
            HStack(spacing: 12) {
                KitCompleteCircle(done: false, tint: entry.overdue ? theme.red500 : nil) { Task { await store.complete(reminder: reminder) } }
                Image(systemName: "bell").font(.system(size: 10))
                    .foregroundStyle(entry.overdue ? theme.red500 : theme.textMuted).frame(width: 12).accessibilityLabel("Reminder")
                TodayRowTitle(text: reminder.title)
                // The snooze buttons take the date's place while the pointer is over the row, so the dates stay in one column
                ZStack(alignment: .trailing) {
                    DueText(date: reminder.dueDate, time: reminder.dueTime, state: entry.overdue ? "overdue" : reminder.dueState)
                        .opacity(hovering ? 0 : 1)
                    HStack(spacing: 4) {
                        Button("+1h") { Task { await store.snooze(reminder, "1hour") } }
                            .buttonStyle(KitButtonStyle(.secondary, small: true)).help("Snooze 1 hour")
                        Button("tmrw") { Task { await store.snooze(reminder, "tomorrow") } }
                            .buttonStyle(KitButtonStyle(.secondary, small: true)).help("Snooze until tomorrow")
                    }
                    .opacity(hovering ? 1 : 0).allowsHitTesting(hovering)
                }
            }
        }
        .contextMenu {
            Button("Mark Complete") { Task { await store.complete(reminder: reminder) } }
            Button("Snooze 1 Hour") { Task { await store.snooze(reminder, "1hour") } }
            Button("Snooze Until Tomorrow") { Task { await store.snooze(reminder, "tomorrow") } }
            Button("Open") { router.open(.reminder(reminder.id)) }
        }
    }
}

// ── Routines ────────────────────────────────────────────────────────────────

struct RoutinesCard: View {
    @Environment(MacRouter.self) private var router
    @Environment(\.theme) private var theme
    let store: TodayStore

    var body: some View {
        KitCard {
            KitCardHeader(title: "Routines", detail: "\(store.routinesDone)/\(store.routines.count) done", uppercase: true) {
                KitLinkButton(title: "All routines →", size: 12, tone: .muted) { router.open(.module("routines")) }
            }
            ForEach(store.routineGroups, id: \.timeOfDay) { group in
                if group.timeOfDay != "anytime" || store.showsAnytimeHeading { KitGroupHeaderRow(text: group.label) }
                ForEach(group.routines) { routine in
                    row(routine)
                    if routine.id != group.routines.last?.id || group.timeOfDay != store.routineGroups.last?.timeOfDay { KitDivider() }
                }
            }
        }
    }

    private func row(_ routine: Routine) -> some View {
        KitRow(onClick: { _, _ in router.open(.routine(routine.id)) }) { _ in
            HStack(spacing: 12) {
                KitCompleteSquare(done: routine.completedToday, enabled: routine.dueToday || routine.completedToday) {
                    Task { await store.toggle(routine: routine) }
                }
                TodayRowTitle(text: routine.title, struck: routine.completedToday)
                if routine.streakCurrent > 0 {
                    Text("🔥 \(routine.streakCurrent)").font(.system(size: 12))
                        .foregroundStyle(routine.completedToday ? theme.amber400 : theme.textMuted).fixedSize()
                        .help("Current streak: \(routine.streakCurrent) days")
                }
                if let days = routine.durationDays, routine.active {
                    Text("Day \(routine.completionCount)/\(days)").font(.system(size: 12)).foregroundStyle(theme.accentText).fixedSize()
                }
                Text(Fmt.freqLabels[routine.frequency] ?? routine.frequency)
                    .font(.system(size: 12)).foregroundStyle(theme.textMuted).fixedSize()
            }
        }
        .contextMenu {
            if routine.dueToday || routine.completedToday {
                Button(routine.completedToday ? "Mark Not Done" : "Mark Done") { Task { await store.toggle(routine: routine) } }
            }
            Button("Open") { router.open(.routine(routine.id)) }
        }
    }
}

// ── Resurfacing ─────────────────────────────────────────────────────────────

struct ResurfacedCard: View {
    @Environment(MacRouter.self) private var router
    @Environment(\.theme) private var theme
    let store: TodayStore

    var body: some View {
        if let note = store.resurfaced {
            KitCard {
                KitCardHeader(title: "Resurfacing", uppercase: true)
                KitRow(onClick: { _, _ in router.open(.note(note.id)) }) { _ in
                    VStack(alignment: .leading, spacing: 6) {
                        Text("From \(Fmt.monthDayYear(note.createdAt))" + (note.type != "note" ? " · \(note.type.capitalized)" : ""))
                            .font(.system(size: 12)).foregroundStyle(theme.textMuted)
                        if !note.title.isEmpty {
                            Text(note.title).font(.system(size: 14, weight: .medium)).foregroundStyle(theme.text200)
                        }
                        Text(note.preview + (note.preview.count >= 200 ? "…" : ""))
                            .font(.system(size: 14)).foregroundStyle(theme.textMuted).lineSpacing(3).lineLimit(3)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contextMenu { Button("Open") { router.open(.note(note.id)) } }
            }
        }
    }
}

// ── Needs Review ────────────────────────────────────────────────────────────

struct ReviewCard: View {
    @Environment(MacRouter.self) private var router
    @Environment(\.theme) private var theme
    let store: TodayStore

    var body: some View {
        KitCard {
            KitCardHeader(title: "Needs Review", uppercase: true, badge: "\(store.needsReviewCount)", badgeTone: .warn)
            ForEach(store.review) { note in
                KitRow(onClick: { _, _ in router.open(.note(note.id)) }) { hovering in
                    HStack(spacing: 12) {
                        TodayRowTitle(text: note.title, muted: false)
                        ZStack(alignment: .trailing) {
                            if let date = note.reviewDate {
                                Text(Fmt.shortDay(date)).font(.system(size: 12)).foregroundStyle(theme.textMuted).fixedSize()
                                    .opacity(hovering ? 0 : 1)
                            }
                            Button("✓ Done") { Task { await store.markReviewed(note) } }
                                .buttonStyle(KitButtonStyle(.secondary, small: true)).help("Mark reviewed")
                                .opacity(hovering ? 1 : 0).allowsHitTesting(hovering)
                        }
                    }
                }
                .contextMenu {
                    Button("Mark Reviewed") { Task { await store.markReviewed(note) } }
                    Button("Open") { router.open(.note(note.id)) }
                }
                KitDivider()
            }
            ForEach(store.stale, id: \.id) { note in
                KitRow(onClick: { _, _ in router.open(.note(note.id)) }) { _ in
                    HStack(spacing: 12) {
                        TodayRowTitle(text: note.title, muted: true)
                        KitBadge(text: "stale \(note.daysAgo)d", tone: .warn)
                        Button("Open →") { router.open(.note(note.id)) }
                            .buttonStyle(KitButtonStyle(.secondary, small: true))
                    }
                }
                .contextMenu { Button("Open") { router.open(.note(note.id)) } }
                if note.id != store.stale.last?.id { KitDivider() }
            }
        }
    }
}
