import SwiftUI

/// The right pane: the selected routine with its streak, heatmap and weekly bars, edited in place and
/// saved automatically, or the "New routine" form (web: routines/show.ejs and form.ejs)
struct RoutineDetailPane: View {
    @Environment(\.theme) private var theme
    @Bindable var model: RoutinesScreenModel

    var body: some View {
        Group {
            if model.newDraft != nil {
                NewRoutineForm(model: model)
            } else if model.rows.count > 1 {
                KitEmptyState(message: "\(model.rows.count) routines selected")
            } else if let session = model.session, let detail = model.store.open, session.routineId == detail.routine.id {
                RoutineEditor(model: model, session: session, detail: detail).id(detail.routine.id)
            } else {
                KitEmptyState(message: "Select a routine.")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.page)
    }
}

/// Title and description
private struct RoutineHeaderFields: View {
    @Environment(\.theme) private var theme
    @Binding var draft: RoutineDraft
    var archived = false
    @Binding var focusTitle: Bool
    var onTitleSubmit: () -> Void
    var onTitleCancel: () -> Void
    var onDescriptionLeave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                KitTitleField(placeholder: "Morning walk, Read 20 pages…", text: $draft.title, onSubmit: onTitleSubmit,
                              onCancel: onTitleCancel, focusRequest: $focusTitle)
                if archived { KitBadge(text: "archived", tone: .neutral) }
            }
            KitTextArea(placeholder: "Optional notes…", text: $draft.description, minHeight: 56,
                        onFocusChange: { focused in if !focused { onDescriptionLeave() } })
        }
        .padding(16)
    }
}

/// When it happens, how often, for how long, tags, notification
private struct RoutineScheduleFields: View {
    @Environment(\.theme) private var theme
    @Binding var draft: RoutineDraft
    let suggestions: [String]
    /// How many days of a time-limited routine are done (shown as "12/30 days")
    var completionCount: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            KitCard {
                VStack(alignment: .leading, spacing: 16) {
                    Grid(alignment: .topLeading, horizontalSpacing: 16, verticalSpacing: 14) {
                        GridRow {
                            KitFieldLabel(text: "Time of day") {
                                KitSelect(options: RoutinesStore.timesOfDay.map { (value: $0, label: RoutinesStore.timeLabels[$0] ?? $0) },
                                          selection: $draft.timeOfDay, label: "Time of day")
                            }
                            KitFieldLabel(text: "Specific time") {
                                KitOptionalDateField(components: .hourAndMinute, value: specificTime, label: "Specific time", emptyLabel: "Set time")
                            }
                            .gridColumnAlignment(.leading)
                        }
                    }
                    KitFieldLabel(text: "Frequency") {
                        KitSelect(options: RoutinesStore.frequencies.map { (value: $0, label: RoutinesStore.frequencyChoiceLabels[$0] ?? $0) },
                                  selection: $draft.frequency, label: "Frequency")
                    }
                    if draft.usesDays {
                        KitFieldLabel(text: "Days") {
                            KitFlowLayout(spacing: 14) {
                                ForEach(Fmt.weekdays, id: \.self) { day in
                                    KitCheckbox(title: day, isOn: Binding(get: { draft.scheduleDays.contains(day) }, set: { on in
                                        if on { draft.scheduleDays.append(day) } else { draft.scheduleDays.removeAll { $0 == day } }
                                    }))
                                }
                            }
                        }
                    }
                    duration
                }
                .padding(16)
            }
            KitCard {
                KitCardHeader(title: "Tags")
                KitTagPicker(tags: $draft.tags, suggestions: suggestions).padding(16)
            }
            .zIndex(1)
            KitCard {
                VStack(alignment: .leading, spacing: 6) {
                    KitCheckbox(title: "Push notification", isOn: $draft.notify)
                    Text("Sends at the specific time set above, via Pushover and/or ntfy (set up in Settings → Notifications).")
                        .font(.system(size: 12)).foregroundStyle(theme.textMuted).padding(.leading, 20)
                }
                .padding(16)
            }
        }
    }

    private var duration: some View {
        VStack(alignment: .leading, spacing: 10) {
            KitFieldLabel(text: "Duration") {
                KitRadioGroup(options: [(value: false, label: "Ongoing"), (value: true, label: "Time-limited")],
                              selection: Binding(get: { draft.durationDays != nil }, set: { limited in
                                  if limited { draft.durationDays = draft.durationDays ?? 30 } else { draft.durationDays = nil; draft.startDate = "" }
                              }), label: "Duration", horizontal: true)
            }
            if let days = draft.durationDays {
                Grid(alignment: .topLeading, horizontalSpacing: 16, verticalSpacing: 10) {
                    GridRow {
                        KitFieldLabel(text: "Duration (days)") {
                            KitNumberField(value: Binding(get: { days }, set: { draft.durationDays = $0 }), range: 1...365, label: "Duration in days")
                        }
                        KitFieldLabel(text: "Start date") {
                            KitOptionalDateField(components: .date, value: startDate, label: "Start date", emptyLabel: "Set date")
                        }
                    }
                }
                HStack(spacing: 8) {
                    if let done = completionCount {
                        Text("\(done)/\(days) days").font(.system(size: 12, weight: .medium)).foregroundStyle(theme.accentText)
                    }
                    Text("Routine auto-archives once the duration is reached.").font(.system(size: 12)).foregroundStyle(theme.textMuted)
                }
            }
        }
    }

    private var specificTime: Binding<Date?> {
        Binding(get: { draft.specificTime.isEmpty ? nil : Fmt.date(fromHHMM: draft.specificTime) },
                set: { draft.specificTime = $0.map { Fmt.hhmm(from: $0) } ?? "" })
    }

    private var startDate: Binding<Date?> {
        Binding(get: { draft.startDate.isEmpty ? nil : Fmt.localDate(draft.startDate) },
                set: { draft.startDate = $0.map { Fmt.ymd($0) } ?? "" })
    }
}

// ── An existing routine ─────────────────────────────────────────────────────

private struct RoutineEditor: View {
    @Environment(\.theme) private var theme
    @Bindable var model: RoutinesScreenModel
    @Bindable var session: RoutineEditSession
    let detail: RoutineDetail

    private var routine: Routine { detail.routine }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                savedLine
                KitCard {
                    RoutineHeaderFields(draft: $session.draft, archived: !routine.active, focusTitle: $model.focusTitle,
                                        onTitleSubmit: { Task { await session.flush() } },
                                        onTitleCancel: { session.revert(\.title) },
                                        onDescriptionLeave: { Task { await session.flush() } })
                    KitDivider()
                    stats
                    if routine.active, routine.dueToday || routine.completedToday { KitDivider(); todayAction }
                    KitDivider()
                    heatmap
                    KitDivider()
                    weekly
                }
                RoutineScheduleFields(draft: $session.draft, suggestions: model.store.allTags,
                                      completionCount: routine.completionCount)
                actions
                footer
            }
            .padding(24)
            .frame(maxWidth: KitWidth.form + 64)
            .frame(maxWidth: .infinity)
        }
        .scrollEdgeEffectHidden(true, for: .top)
        .onChange(of: session.draft.tags) { Task { await session.flush() } }
        .onChange(of: session.draft.timeOfDay) { Task { await session.flush() } }
        .onChange(of: session.draft.specificTime) { Task { await session.flush() } }
        .onChange(of: session.draft.frequency) { Task { await session.flush() } }
        .onChange(of: session.draft.scheduleDays) { Task { await session.flush() } }
        .onChange(of: session.draft.durationDays) { Task { await session.flush() } }
        .onChange(of: session.draft.startDate) { Task { await session.flush() } }
        .onChange(of: session.draft.notify) { Task { await session.flush() } }
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

    // ── Streak numbers, today, heatmap, bars ────────────────────────────────

    private var stats: some View {
        HStack(spacing: 0) {
            figure("\(routine.streakCurrent)", "Current streak", tint: theme.amber400)
            Rectangle().fill(theme.border1).frame(width: 1)
            figure("\(routine.streakBest)", "Best streak", tint: theme.text300)
            Rectangle().fill(theme.border1).frame(width: 1)
            figure("\(routine.completionCount)", "Total completions", tint: theme.text300)
        }
        .frame(height: 78)
        .accessibilityElement(children: .combine)
    }

    private func figure(_ value: String, _ label: String, tint: Color) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 26, weight: .bold)).foregroundStyle(tint)
            Text(label).font(.system(size: 12)).foregroundStyle(theme.textMuted)
        }
        .frame(maxWidth: .infinity)
    }

    private var todayAction: some View {
        HStack {
            Button { Task { await model.toggleToday(routine.id) } } label: {
                Label(routine.completedToday ? "Done today — click to undo" : "Mark done for today",
                      systemImage: routine.completedToday ? "checkmark.circle.fill" : "checkmark.circle")
            }
            .buttonStyle(KitButtonStyle(.secondary))
            .fixedSize()
            Spacer()
        }
        .padding(16)
    }

    private var heatmap: some View {
        let weeks = detail.heatmap.map { week in
            week.map { cell -> KitHeatCell in
                let kind: KitHeatCell.Kind = cell.isFuture ? .future : cell.completed ? .done : cell.notApplicable ? .notScheduled : .missed
                return KitHeatCell(kind: kind, tooltip: cell.label + (cell.completed ? " ✓" : cell.notApplicable ? " —" : ""))
            }
        }
        let days = detail.heatmap.flatMap { $0 }.filter { !$0.isFuture && !$0.notApplicable }
        let done = days.filter(\.completed).count
        return VStack(alignment: .leading, spacing: 10) {
            Text("Last 12 weeks").font(.system(size: 12, weight: .medium)).foregroundStyle(theme.textMuted)
            KitHeatmap(weeks: weeks, leadingCaption: detail.heatmap.first?.first?.label ?? "",
                       summary: "Last 12 weeks: \(done) of \(days.count) scheduled days done")
        }
        .padding(16)
    }

    private var weekly: some View {
        let bars = detail.weeklyStats.map { s -> KitBar in
            KitBar(fraction: Double(s.rate) / 100, tone: s.rate >= 80 ? .good : s.rate >= 50 ? .fair : s.rate > 0 ? .low : .none,
                   tooltip: "\(s.label): \(s.completionCount)/\(s.dayCount) days (\(s.rate)%)")
        }
        return VStack(alignment: .leading, spacing: 10) {
            Text("Weekly completion rate").font(.system(size: 12, weight: .medium)).foregroundStyle(theme.textMuted)
            KitBarChart(bars: bars, leadingCaption: detail.weeklyStats.first?.label ?? "",
                        summary: "Weekly completion rate over the last \(bars.count) weeks")
        }
        .padding(16)
    }

    // ── Buttons and footer ──────────────────────────────────────────────────

    private var actions: some View {
        HStack(spacing: 10) {
            Button(routine.active ? "Archive" : "Restore") { Task { await model.toggleArchived(routine.id) } }
                .buttonStyle(KitButtonStyle(.secondary)).fixedSize()
            Spacer(minLength: 8)
            Button("Delete") { model.requestDelete([routine.id]) }.buttonStyle(KitButtonStyle(.danger)).fixedSize()
        }
    }

    @ViewBuilder private var footer: some View {
        if let created = routine.createdAt {
            Text("Created \(Fmt.monthDayYear(created))").font(.system(size: 12)).foregroundStyle(theme.textMuted)
        }
    }
}

// ── A routine being made ────────────────────────────────────────────────────

private struct NewRoutineForm: View {
    @Environment(\.theme) private var theme
    @Bindable var model: RoutinesScreenModel

    var body: some View {
        let draft = Binding(get: { model.newDraft ?? RoutineDraft() }, set: { model.newDraft = $0 })
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("New routine").font(.system(size: 20, weight: .bold)).foregroundStyle(theme.textPrimary)
                KitCard {
                    RoutineHeaderFields(draft: draft, focusTitle: $model.focusTitle,
                                        onTitleSubmit: { Task { await model.addNew() } }, onTitleCancel: {}, onDescriptionLeave: {})
                }
                RoutineScheduleFields(draft: draft, suggestions: model.store.allTags, completionCount: nil)
                HStack(spacing: 10) {
                    Button("Add routine") { Task { await model.addNew() } }
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
