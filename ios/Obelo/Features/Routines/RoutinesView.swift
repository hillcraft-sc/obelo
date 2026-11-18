import SwiftUI

// Routines — views/routines/index.ejs, show.ejs, form.ejs.

struct RoutinesView: View {
    @Environment(AppState.self) private var app
    @Environment(Toast.self) private var toast
    @Environment(\.theme) private var theme

    struct Response: Decodable { let routines: [Routine]; let tags: [String] }

    @State private var view = "today"
    @State private var tag: String?
    @State private var routines: [Routine]?
    @State private var tags: [String] = []
    @State private var error: String?
    @State private var showNew = false

    var body: some View {
        Page(refresh: load) {
            PageHeader(title: "Routines", subtitle: "Habits that repeat on a schedule.", pageName: true) {
                PrimaryButton(title: "New routine", systemImage: "plus") { showNew = true }
            }
            SectionTabs(tabs: [SectionTab(key: "today", label: "Today"), SectionTab(key: "archived", label: "Archived")], selection: $view)
            TagFilter(tags: tags, selected: $tag)
            if let error { Banner(kind: .error, text: error) }
            if let routines { content(routines) } else { ProgressView().frame(maxWidth: .infinity).padding(40) }
        }
        .task(id: "\(view)|\(tag ?? "")|\(app.dataVersion)") { await load() }
        .onNewItem("routines") { showNew = true }
        .sheet(isPresented: $showNew) { RoutineForm(routine: nil) { Task { await load() } } }
    }

    @ViewBuilder private func content(_ routines: [Routine]) -> some View {
        // Same wording as views/routines/index.ejs
        if routines.isEmpty && view != "archived" {
            Card {
                if tag != nil { EmptyRow(text: "No routines match this filter.", action: EmptyAction(label: "Clear filter") { tag = nil }) }
                else { EmptyRow(text: "No routines yet.", action: EmptyAction(label: "New routine") { showNew = true }) }
            }
        } else if view == "today" {
            let due = routines.filter(\.dueToday)
            let notDue = routines.filter { !$0.dueToday }
            if due.isEmpty { Card { EmptyRow(text: "Nothing due today.") } }
            ForEach(Fmt.timeOfDay, id: \.self) { tod in
                let group = due.filter { $0.timeOfDay == tod || (tod == "anytime" && !Fmt.timeOfDay.contains($0.timeOfDay)) }
                if !group.isEmpty {
                    section(Fmt.timeLabels[tod] ?? tod, group)
                }
            }
            if !notDue.isEmpty {
                section("Not due today", notDue).opacity(0.6)
            }
        } else {
            let finished = routines.filter { $0.finishedChallenge == true }
            let archived = routines.filter { $0.finishedChallenge != true }
            if routines.isEmpty { Card { EmptyRow(text: "No archived routines yet.") } }
            if !finished.isEmpty { section("Completed Streaks", finished) }
            if !archived.isEmpty { section("Archived", archived) }
        }
    }

    private func section(_ title: String, _ items: [Routine]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).font(.system(size: 12, weight: .semibold)).tracking(1.2)
                .foregroundStyle(theme.textMuted).padding(.horizontal, 4)
            Card {
                ForEach(Array(items.enumerated()), id: \.element.id) { i, r in
                    if i > 0 { RowDivider() }
                    SwipeRow(onComplete: r.dueToday && !r.completedToday ? { toggle(r) } : nil) {
                        RoutineRow(routine: r) { toggle(r) }
                    }
                }
            }
        }
    }

    private func load() async {
        do {
            let r: Response = try await APIClient.shared.get("/routines", query: ["view": view, "tag": tag])
            withAnimation(.easeOut(duration: 0.15)) { routines = r.routines }
            tags = r.tags
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    private func toggle(_ r: Routine) {
        if let i = routines?.firstIndex(where: { $0.id == r.id }) {
            withAnimation(.easeOut(duration: 0.15)) { routines?[i].completedToday.toggle() }
        }
        toast.run {
            struct R: Decodable { let routine: Routine }
            let res: R = try await APIClient.shared.post("/routines/\(r.id)/complete")
            if let i = routines?.firstIndex(where: { $0.id == r.id }) { routines?[i] = res.routine }
            app.dataChanged()
        }
    }
}

struct RoutineDetailView: View {
    @Environment(AppState.self) private var app
    @Environment(Toast.self) private var toast
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    let id: Int

    struct Detail: Decodable { let routine: Routine; let heatmap: [[HeatmapDay]]; let weeklyStats: [WeeklyStat] }

    @State private var detail: Detail?
    @State private var error: String?
    @State private var editing = false
    @State private var confirmDelete = false

    var body: some View {
        Loadable(value: detail, error: error, retry: load) { d in
            Page(refresh: load) {
                Card {
                    header(d.routine)
                    stats(d.routine)
                    if d.routine.active { completeBar(d.routine) }
                    heatmap(d.heatmap)
                    weekly(d.weeklyStats)
                }
                HStack {
                    SecondaryButton(title: d.routine.active ? "Archive" : "Restore", systemImage: d.routine.active ? "archivebox" : "arrow.uturn.backward") {
                        toast.run {
                            try await APIClient.shared.post("/routines/\(id)/archive")
                            app.dataChanged(); await load()
                        }
                    }
                    Spacer()
                    SecondaryButton(title: "Delete", systemImage: "trash", tint: theme.red400) { confirmDelete = true }
                }
            }
        }
        .themedNavBar(theme, title: "Routines")
        .toolbar { ToolbarItem(placement: .primaryAction) { Button("Edit") { editing = true }.disabled(detail == nil) } }
        .task { await load() }
        .sheet(isPresented: $editing) {
            if let r = detail?.routine { RoutineForm(routine: r) { Task { await load(); app.dataChanged() } } }
        }
        .confirmationDialog("Delete this routine and its history?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                toast.run { try await APIClient.shared.delete("/routines/\(id)"); app.dataChanged(); dismiss() }
            }
        }
    }

    private func chip(_ text: String, accent: Bool = false) -> some View {
        Text(text).font(.system(size: 12))
            .foregroundStyle(accent ? theme.accentTextLight : theme.text400)
            .padding(.horizontal, 8).padding(.vertical, 2)
            .background(accent ? theme.accentSurface : theme.elevated, in: Capsule())
            .overlay(Capsule().stroke(accent ? theme.accentBorder9 : theme.border2, lineWidth: 1))
    }

    private func header(_ r: Routine) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(r.title).font(.system(size: 20, weight: .semibold)).foregroundStyle(r.active ? theme.textPrimary : theme.textMuted)
                if !r.active { chip("archived") }
            }
            if !r.description.isEmpty { Text(r.description).font(.system(size: 14)).foregroundStyle(theme.textMuted) }
            FlowLayout(spacing: 8) {
                chip(Fmt.freqLabels[r.frequency] ?? r.frequency)
                chip(Fmt.timeLabels[r.timeOfDay] ?? r.timeOfDay)
                if ["weekly", "custom"].contains(r.frequency), !r.scheduleDays.isEmpty { chip(r.scheduleDays.joined(separator: ", ")) }
                if let t = r.specificTime { chip(Fmt.time(t, hour12: app.hour12)) }
                if let days = r.durationDays { chip("\(days)-day challenge", accent: true) }
                ForEach(r.tags, id: \.self) { chip("#\($0)") }
            }
        }
        .padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { RowDivider() }
    }

    private func stats(_ r: Routine) -> some View {
        HStack(spacing: 0) {
            stat("\(r.streakCurrent)", "Current streak", theme.amber400)
            Rectangle().fill(theme.border1).frame(width: 1)
            stat("\(r.streakBest)", "Best streak", theme.text300)
            Rectangle().fill(theme.border1).frame(width: 1)
            stat("\(r.completionCount)", "Total completions", theme.text300)
        }
        .fixedSize(horizontal: false, vertical: true)
        .overlay(alignment: .bottom) { RowDivider() }
    }

    private func stat(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 24, weight: .bold)).foregroundStyle(color)
            Text(label).font(.system(size: 12)).foregroundStyle(theme.textMuted)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 16)
    }

    private func completeBar(_ r: Routine) -> some View {
        HStack {
            if r.dueToday || r.completedToday {
                Button {
                    toast.run {
                        try await APIClient.shared.post("/routines/\(id)/complete")
                        app.dataChanged(); await load()
                    }
                } label: {
                    Label(r.completedToday ? "Done today" : "Mark done today", systemImage: "checkmark")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(r.completedToday ? theme.green400 : theme.onAccent)
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .background(r.completedToday ? theme.green500.opacity(0.15) : theme.accent, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(r.completedToday ? theme.green500.opacity(0.5) : .clear, lineWidth: 1))
                }
                .buttonStyle(PressableStyle())
            } else {
                Text("Not scheduled today").font(.system(size: 14)).foregroundStyle(theme.textMuted)
            }
            Spacer()
        }
        .padding(.horizontal, 24).padding(.vertical, 16)
        .overlay(alignment: .bottom) { RowDivider() }
    }

    private func heatmap(_ weeks: [[HeatmapDay]]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Last 12 weeks").font(.system(size: 12, weight: .medium)).foregroundStyle(theme.textMuted)
            HStack(spacing: 4) {
                ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                    VStack(spacing: 4) {
                        ForEach(week, id: \.dateStr) { cell in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(cell.isFuture ? .clear : cell.completed ? theme.green500 : cell.notApplicable ? theme.elevated.opacity(0.3) : theme.elevated)
                                .aspectRatio(1, contentMode: .fit)
                                .accessibilityLabel("\(cell.label)\(cell.completed ? ", done" : "")")
                        }
                    }
                }
            }
            .frame(maxWidth: 12 * 20)
            HStack {
                Text(weeks.first?.first?.label ?? "")
                Spacer()
                Text("Today")
            }
            .font(.system(size: 10)).foregroundStyle(theme.textMuted)
            .frame(maxWidth: 12 * 20)
        }
        .padding(.horizontal, 24).padding(.vertical, 20)
    }

    private func weekly(_ stats: [WeeklyStat]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Weekly completion rate").font(.system(size: 12, weight: .medium)).foregroundStyle(theme.textMuted)
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(stats, id: \.label) { s in
                    UnevenRoundedRectangle(topLeadingRadius: 3, topTrailingRadius: 3)
                        .fill(s.rate >= 80 ? theme.green500 : s.rate >= 50 ? Color(hex: "#6366f1") : s.rate > 0 ? Color(hex: "#374151") : Color(hex: "#111827"))
                        .frame(height: max(s.rate > 0 ? 3 : 0, CGFloat(s.rate) * 0.64))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 64, alignment: .bottom)
            HStack {
                Text(stats.first?.label ?? "")
                Spacer()
                Text("This week")
            }
            .font(.system(size: 10)).foregroundStyle(theme.textMuted)
        }
        .padding(.horizontal, 24).padding(.bottom, 20).padding(.top, 16)
        .overlay(alignment: .top) { RowDivider() }
    }

    private func load() async {
        do { detail = try await APIClient.shared.get("/routines/\(id)") }
        catch { self.error = error.localizedDescription }
    }
}

/// routines/form.ejs
struct RoutineForm: View {
    @Environment(\.theme) private var theme
    let routine: Routine?
    let saved: () -> Void

    @State private var title = ""
    @State private var description = ""
    @State private var timeOfDay = "anytime"
    @State private var specificTime: String?
    @State private var frequency = "daily"
    @State private var scheduleDays: [String] = []
    @State private var challenge = false
    @State private var durationDays = 30
    @State private var startDate: String?
    @State private var notify = false
    @State private var tags: [String] = []
    @State private var allTags: [String] = []
    @State private var error: String?
    @State private var loaded = false

    var body: some View {
        FormSheet(title: routine == nil ? "New Routine" : "Edit Routine", saveTitle: routine == nil ? "Create" : "Save",
                  canSave: !title.trimmingCharacters(in: .whitespaces).isEmpty, error: error, save: save) {
            FormSection(label: "Title") { ThemedField(placeholder: "e.g. Morning stretch", text: $title) }
            FormSection(label: "Description") { ThemedField(placeholder: "Optional", text: $description, axis: .vertical).lineLimit(2...6) }
            HStack(spacing: 12) {
                FormSection(label: "Frequency") {
                    SelectField(options: ["daily", "weekdays", "weekends", "weekly", "custom"].map { ($0, Fmt.freqLabels[$0]!) }, selection: $frequency)
                }
                FormSection(label: "Time of day") {
                    SelectField(options: Fmt.timeOfDay.map { ($0, Fmt.timeLabels[$0]!) }, selection: $timeOfDay)
                }
            }
            if frequency == "weekly" || frequency == "custom" {
                FormSection(label: "Days") {
                    HStack(spacing: 6) {
                        ForEach(Fmt.weekdays, id: \.self) { day in
                            let on = scheduleDays.contains(day)
                            Button {
                                if on { scheduleDays.removeAll { $0 == day } } else { scheduleDays.append(day) }
                            } label: {
                                Text(day).font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(on ? theme.onAccent : theme.text400)
                                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                                    .background(on ? theme.accent : theme.elevated, in: RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            FormSection(label: "Specific time") { OptionalTimeField(hhmm: $specificTime) }
            ToggleRow(title: "Time-limited challenge", subtitle: "Archives itself when you reach the goal", isOn: $challenge)
            if challenge {
                Stepper(value: $durationDays, in: 1...365) {
                    Text("\(durationDays) days").font(.system(size: 14)).foregroundStyle(theme.text200)
                }
                FormSection(label: "Start date") { OptionalDateField(ymd: $startDate) }
            }
            ToggleRow(title: "Notify me", subtitle: "Push notification at the routine's time", isOn: $notify)
            FormSection(label: "Tags") { TagsField(tags: $tags, suggestions: allTags) }
        }
        .task {
            guard !loaded else { return }
            loaded = true
            if let r = routine {
                title = r.title; description = r.description; timeOfDay = r.timeOfDay; specificTime = r.specificTime
                frequency = r.frequency; scheduleDays = r.scheduleDays; challenge = r.durationDays != nil
                durationDays = r.durationDays ?? 30; startDate = r.startDate; notify = r.notify; tags = r.tags
            }
            struct T: Decodable { let tags: [String] }
            allTags = ((try? await APIClient.shared.get("/tags")) as T?)?.tags ?? []
        }
    }

    private func save() async -> Bool {
        let body: [String: Any] = [
            "title": title, "description": description, "timeOfDay": timeOfDay, "specificTime": specificTime ?? NSNull(),
            "frequency": frequency, "scheduleDays": Fmt.weekdays.filter(scheduleDays.contains),
            "durationDays": challenge ? durationDays : NSNull(), "startDate": challenge ? (startDate as Any? ?? NSNull()) as Any : NSNull(),
            "notify": notify, "tags": tags,
        ]
        do {
            if let routine { try await APIClient.shared.post("/routines/\(routine.id)", body, method: "PUT") }
            else { try await APIClient.shared.post("/routines", body) }
            saved()
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }
}
