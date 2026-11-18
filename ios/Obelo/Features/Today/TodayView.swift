import SwiftUI

// Today — views/dashboard/index.ejs: date + clock, "N tasks slipping", then the user's widgets
// in their saved order (My Focus, Today's Events, Due Today & Overdue, Routines, Resurfacing,
// Needs Review) and Quick Capture.

struct TodayView: View {
    @Environment(AppState.self) private var app
    @Environment(Toast.self) private var toast
    @Environment(\.theme) private var theme
    @State private var data: Dashboard?
    @State private var error: String?
    @State private var quickCapture = ""
    @State private var capturePrefill: String?

    var body: some View {
        Loadable(value: data, error: error, retry: load) { d in
            Page(refresh: load) {
                header(d)
                ForEach(d.widgets.filter(\.enabled), id: \.key) { widget in
                    switch widget.key {
                    case "focus": focusCard(d)
                    case "calendar": eventsCard(d)
                    case "due_items": if !d.due.isEmpty { dueCard(d) }
                    case "routines": if !d.routines.isEmpty { routinesCard(d) }
                    case "resurfaced": if let note = d.resurfaced { resurfacedCard(note) }
                    case "review": if !d.review.isEmpty || !d.stale.isEmpty { reviewCard(d) }
                    default: EmptyView()
                    }
                }
                quickCaptureCard
            }
        }
        .task(id: app.dataVersion) { await load() }
        .navigationDestination(item: $capturePrefill) { text in
            CaptureView(prefill: text).themedNavBar(theme, title: "Capture")
        }
    }

    private func load() async {
        do {
            let d: Dashboard = try await APIClient.shared.get("/dashboard")
            withAnimation(.easeOut(duration: 0.2)) { data = d }
            error = nil
        } catch {
            if data == nil { self.error = error.localizedDescription }
        }
    }

    // ── Header ───────────────────────────────────────────────────────────────

    private func header(_ d: Dashboard) -> some View {
        HStack(alignment: .firstTextBaseline) {
            TimelineView(.everyMinute) { context in
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.date.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                        .font(.system(size: 24, weight: .bold)).foregroundStyle(theme.textPrimary)
                    Text(Fmt.clock(context.date, hour12: app.hour12, tz: .current))
                        .font(.system(size: 14)).foregroundStyle(theme.textMuted)
                }
            }
            Spacer()
            if d.slippingCount > 0 {
                NavigationLink(value: Route.module("tasks")) {
                    Text("\(d.slippingCount) task\(d.slippingCount == 1 ? "" : "s") slipping")
                        .font(.system(size: 12)).foregroundStyle(theme.amber400)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.amber900, lineWidth: 1))
                }
            }
        }
    }

    // ── My Focus ─────────────────────────────────────────────────────────────

    private func focusCard(_ d: Dashboard) -> some View {
        Card {
            CardHeader(title: "My Focus") {
                NavigationLink(value: Route.module("tasks")) { linkText("All tasks →") }
            }
            if d.focusTasks.isEmpty {
                Text("No tasks set to \"Today\" status.")
                    .font(.system(size: 14)).italic().foregroundStyle(theme.textMuted)
                    .padding(.horizontal, 20).padding(.vertical, 16)
            } else {
                ForEach(Array(d.focusTasks.enumerated()), id: \.element.id) { i, task in
                    if i > 0 { RowDivider() }
                    HStack(spacing: 12) {
                        CompleteCircle(ring: theme.accentHover) { complete(task: task) }
                        Dot(color: theme.priorityDot(task.priority), size: 10)
                        NavigationLink(value: Route.task(task.id)) {
                            Text(task.title).font(.system(size: 14, weight: .medium)).foregroundStyle(theme.text100)
                                .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if let time = task.dueTime {
                            Text(Fmt.time(time, hour12: app.hour12)).font(.system(size: 12)).foregroundStyle(theme.textMuted)
                        }
                    }
                    .padding(.horizontal, 20).padding(.vertical, 14)
                }
            }
        }
    }

    // ── Today's Events ───────────────────────────────────────────────────────

    private func eventsCard(_ d: Dashboard) -> some View {
        Card {
            CardHeader(title: "Today's Events") {
                NavigationLink(value: Route.module("calendar")) { linkText("Calendar →") }
            }
            if d.events.isEmpty {
                Text("No events today.").font(.system(size: 14)).italic().foregroundStyle(theme.textMuted)
                    .padding(.horizontal, 20).padding(.vertical, 16)
            } else {
                ForEach(Array(d.events.enumerated()), id: \.element.id) { i, ev in
                    if i > 0 { RowDivider() }
                    NavigationLink(value: Route.event(ev)) {
                        HStack(spacing: 12) {
                            Dot(color: Color(hex: ev.color))
                            Text(ev.title).font(.system(size: 14)).foregroundStyle(theme.text200).lineLimit(1)
                            Spacer()
                            Text(ev.allDay ? "All day" : Fmt.clock(ev.startAt, hour12: app.hour12, tz: userTZ))
                                .font(.system(size: 12)).foregroundStyle(theme.textMuted)
                        }
                        .padding(.horizontal, 20).padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // ── Due Today & Overdue ──────────────────────────────────────────────────

    private func dueCard(_ d: Dashboard) -> some View {
        Card {
            CardHeader(title: "Due Today & Overdue", badge: "\(d.due.count)") {
                HStack(spacing: 12) {
                    NavigationLink(value: Route.module("tasks")) { linkText("Tasks →") }
                    NavigationLink(value: Route.module("reminders")) { linkText("Reminders →") }
                }
            }
            ForEach(Array(d.due.enumerated()), id: \.element.id) { i, entry in
                if i > 0 { RowDivider() }
                dueRow(entry)
            }
        }
    }

    @ViewBuilder private func dueRow(_ entry: Dashboard.DueEntry) -> some View {
        let ring = entry.overdue ? theme.red500 : theme.border3
        let dueColor = entry.overdue ? theme.red400 : (entry.task?.dueState ?? entry.reminder?.dueState) == "today" ? theme.green400 : theme.textMuted
        if let task = entry.task {
            HStack(spacing: 12) {
                CompleteCircle(ring: ring) { complete(task: task) }
                Dot(color: theme.priorityDot(task.priority))
                NavigationLink(value: Route.task(task.id)) {
                    Text(task.title).font(.system(size: 14)).foregroundStyle(theme.text200).lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Text(Fmt.due(task.dueDate, task.dueTime, hour12: app.hour12)).font(.system(size: 12)).foregroundStyle(dueColor)
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
        } else if let r = entry.reminder {
            HStack(spacing: 12) {
                CompleteCircle(ring: ring) { complete(reminder: r) }
                Image(systemName: "bell").font(.system(size: 12)).foregroundStyle(entry.overdue ? theme.red500 : theme.textMuted)
                NavigationLink(value: Route.reminder(r.id)) {
                    Text(r.title).font(.system(size: 14)).foregroundStyle(theme.text200).lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Text(Fmt.due(r.dueDate, r.dueTime, hour12: app.hour12)).font(.system(size: 12)).foregroundStyle(dueColor)
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
            .contextMenu {
                Button("Snooze 1 hour", systemImage: "clock") { snooze(r, "1hour") }
                Button("Snooze until tomorrow", systemImage: "sunrise") { snooze(r, "tomorrow") }
            }
        }
    }

    // ── Routines ─────────────────────────────────────────────────────────────

    private func routinesCard(_ d: Dashboard) -> some View {
        let done = d.routines.filter(\.completedToday).count
        let groups = Fmt.timeOfDay.map { tod in (tod, d.routines.filter { ($0.timeOfDay == tod) || (tod == "anytime" && !Fmt.timeOfDay.contains($0.timeOfDay)) }) }
        let hasTimed = groups.contains { $0.0 != "anytime" && !$0.1.isEmpty }
        return Card {
            CardHeader(title: "Routines", note: "\(done)/\(d.routines.count) done") {
                NavigationLink(value: Route.module("routines")) { linkText("All routines →") }
            }
            ForEach(groups, id: \.0) { tod, routines in
                if !routines.isEmpty {
                    if tod != "anytime" || hasTimed { GroupLabel(title: Fmt.timeLabels[tod] ?? tod) }
                    ForEach(Array(routines.enumerated()), id: \.element.id) { i, r in
                        if i > 0 { RowDivider() }
                        RoutineRow(routine: r) { toggle(routine: r) }
                    }
                }
            }
        }
    }

    // ── Resurfacing ──────────────────────────────────────────────────────────

    private func resurfacedCard(_ note: Dashboard.Resurfaced) -> some View {
        Card {
            CardHeader(title: "Resurfacing")
            NavigationLink(value: Route.note(note.id)) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("From \(Fmt.monthDayYear(note.createdAt))\(note.type != "note" ? " · \(note.type.capitalized)" : "")")
                        .font(.system(size: 12)).foregroundStyle(theme.textMuted)
                    if !note.title.isEmpty {
                        Text(note.title).font(.system(size: 14, weight: .medium)).foregroundStyle(theme.text200)
                    }
                    Text(note.preview + (note.preview.count >= 200 ? "…" : ""))
                        .font(.system(size: 14)).foregroundStyle(theme.textMuted).lineLimit(3).lineSpacing(3)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20).padding(.vertical, 16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // ── Needs Review ─────────────────────────────────────────────────────────

    private func reviewCard(_ d: Dashboard) -> some View {
        Card {
            CardHeader(title: "Needs Review", badge: "\(d.review.count + d.stale.count)", badgeWarn: true)
            ForEach(Array(d.review.enumerated()), id: \.element.id) { i, note in
                if i > 0 { RowDivider() }
                HStack(spacing: 12) {
                    NavigationLink(value: Route.note(note.id)) {
                        Text(note.title).font(.system(size: 14)).foregroundStyle(theme.text300).lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if let date = note.reviewDate {
                        Text(Fmt.shortDay(date)).font(.system(size: 12)).foregroundStyle(theme.textMuted)
                    }
                    Button { markReviewed(note) } label: {
                        Text("✓ Done").font(.system(size: 12)).foregroundStyle(theme.textMuted)
                            .padding(.horizontal, 8).padding(.vertical, 2)
                            .background(theme.elevated, in: RoundedRectangle(cornerRadius: 4))
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(theme.border2, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20).padding(.vertical, 12)
            }
            ForEach(Array(d.stale.enumerated()), id: \.element.id) { i, note in
                if i > 0 || !d.review.isEmpty { RowDivider() }
                NavigationLink(value: Route.note(note.id)) {
                    HStack(spacing: 12) {
                        Text(note.title).font(.system(size: 14)).foregroundStyle(theme.text400).lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Badge(text: "stale \(note.daysAgo)d", fg: theme.amber500, bg: theme.amber950, border: theme.amber900)
                        Text("Open →").font(.system(size: 12)).foregroundStyle(theme.textMuted)
                    }
                    .padding(.horizontal, 20).padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // ── Quick Capture ────────────────────────────────────────────────────────

    private var quickCaptureCard: some View {
        Card(padding: 20) {
            Text("QUICK CAPTURE").font(.system(size: 12, weight: .semibold)).tracking(0.6)
                .foregroundStyle(theme.textMuted).padding(.bottom, 12)
            HStack(spacing: 8) {
                ThemedField(placeholder: "Capture a thought, task, or note…", text: $quickCapture) { submitCapture() }
                PrimaryButton(title: "Capture") { submitCapture() }
            }
        }
    }

    private func submitCapture() {
        let text = quickCapture.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        quickCapture = ""
        capturePrefill = text
    }

    // ── Actions ──────────────────────────────────────────────────────────────

    private var userTZ: TimeZone { TimeZone(identifier: app.me?.user.timezone ?? "") ?? .current }

    private func linkText(_ s: String) -> some View {
        Text(s).font(.system(size: 12)).foregroundStyle(theme.textMuted)
    }

    private func complete(task: TaskItem) {
        withAnimation(.easeOut(duration: 0.25)) {
            data?.focusTasks.removeAll { $0.id == task.id }
            data?.due.removeAll { $0.task?.id == task.id }
        }
        toast.run {
            try await APIClient.shared.post("/tasks/\(task.id)/complete")
            if task.recurring { await load() }
        }
    }

    private func complete(reminder: ReminderItem) {
        withAnimation(.easeOut(duration: 0.25)) { data?.due.removeAll { $0.reminder?.id == reminder.id } }
        toast.run {
            try await APIClient.shared.post("/reminders/\(reminder.id)/complete")
            if reminder.recurring { await load() }
        }
    }

    private func snooze(_ r: ReminderItem, _ duration: String) {
        withAnimation(.easeOut(duration: 0.25)) { data?.due.removeAll { $0.reminder?.id == r.id } }
        toast.run {
            try await APIClient.shared.post("/reminders/\(r.id)/snooze", ["duration": duration])
            toast.show(duration == "tomorrow" ? "Snoozed until tomorrow" : "Snoozed 1 hour")
        }
    }

    private func toggle(routine: Routine) {
        guard let i = data?.routines.firstIndex(where: { $0.id == routine.id }) else { return }
        withAnimation(.easeOut(duration: 0.15)) { data?.routines[i].completedToday.toggle() }
        toast.run {
            struct R: Decodable { let routine: Routine }
            let r: R = try await APIClient.shared.post("/routines/\(routine.id)/complete")
            if let j = data?.routines.firstIndex(where: { $0.id == routine.id }) { data?.routines[j] = r.routine }
        }
    }

    private func markReviewed(_ note: Dashboard.ReviewNote) {
        withAnimation(.easeOut(duration: 0.25)) { data?.review.removeAll { $0.id == note.id } }
        toast.run { try await APIClient.shared.post("/notes/\(note.id)/flag") }
    }
}

/// routines/_row.ejs
struct RoutineRow: View {
    @Environment(\.theme) private var theme
    let routine: Routine
    let toggle: () -> Void

    var body: some View {
        let canToggle = routine.completedToday || routine.dueToday
        HStack(spacing: 12) {
            CompleteSquare(done: routine.completedToday, enabled: canToggle, action: toggle)
            NavigationLink(value: Route.routine(routine.id)) {
                Text(routine.title)
                    .font(.system(size: 14))
                    .strikethrough(routine.completedToday, color: theme.textMuted)
                    .foregroundStyle(routine.completedToday ? theme.textMuted : theme.text200)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if routine.streakCurrent > 0 {
                Text("🔥 \(routine.streakCurrent)").font(.system(size: 12))
                    .foregroundStyle(routine.completedToday ? theme.amber400 : theme.textMuted)
            }
            if let days = routine.durationDays, routine.active {
                Text("Day \(routine.completionCount)/\(days)").font(.system(size: 12)).foregroundStyle(theme.accentText)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }
}
