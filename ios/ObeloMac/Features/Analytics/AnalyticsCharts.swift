import SwiftUI

/// A chart card: title, one plain line of explanation, a small line of what is counted, then the content
/// (web: the bg-gray-900 cards on analytics/index.ejs)
private struct AnalyticsCard<Trailing: View, Content: View>: View {
    @Environment(\.theme) private var theme
    let title: String
    let explain: String
    let subtitle: String
    @ViewBuilder var trailing: Trailing
    @ViewBuilder var content: Content

    var body: some View {
        KitCard {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(theme.text100)
                            .accessibilityAddTraits(.isHeader)
                        Text(explain).font(.system(size: 12)).foregroundStyle(theme.textMuted).padding(.bottom, 4)
                        Text(subtitle).font(.system(size: 12)).foregroundStyle(theme.textMuted)
                    }
                    Spacer(minLength: 8)
                    trailing
                }
                .padding(.bottom, 14)
                content
            }
            .padding(20)
        }
    }
}

extension AnalyticsCard where Trailing == EmptyView {
    fileprivate init(title: String, explain: String, subtitle: String, @ViewBuilder content: () -> Content) {
        self.init(title: title, explain: explain, subtitle: subtitle, trailing: { EmptyView() }, content: content)
    }
}

private struct AnalyticsEmpty: View {
    @Environment(\.theme) private var theme
    let text: String
    var body: some View {
        Text(text).font(.system(size: 14)).foregroundStyle(theme.textMuted)
            .frame(maxWidth: .infinity, minHeight: 90)
    }
}

/// Every chart card below the summary
struct AnalyticsCharts: View {
    @Environment(\.theme) private var theme
    let store: AnalyticsStore
    let data: Analytics
    let wide: Bool

    var body: some View {
        VStack(spacing: 16) {
            timing
            pair(data.hasOnTimeRateTrend ? AnyView(trend) : nil, AnyView(timeOfDay))
            pair(AnyView(priority), AnyView(heatmap))
            velocity
            routines
        }
    }

    /// Two cards side by side when the window is wide, otherwise one under the other
    @ViewBuilder private func pair(_ a: AnyView?, _ b: AnyView) -> some View {
        if let a {
            if wide { HStack(alignment: .top, spacing: 16) { a; b } } else { VStack(spacing: 16) { a; b } }
        } else { b }
    }

    // ── Colours ─────────────────────────────────────────────────────────────

    private func color(_ key: String) -> Color {
        switch key {
        case "early": theme.green500
        case "on_time": theme.accent
        case "late_same_day": theme.yellow400
        case "late_1_3": theme.orange500
        case "late_4_7": theme.orange800
        default: theme.red500
        }
    }

    // ── Completion Timing ───────────────────────────────────────────────────

    private var timing: some View {
        AnalyticsCard(title: "Completion Timing",
                      explain: "When you finished things compared with when they were due: early, on time, or late.",
                      subtitle: "Items with due dates · \(data.rangeLabel) · 30-min grace window") {
            KitChartLegend(items: Analytics.Week.buckets.map { ($0.label, color($0.key)) })
                .padding(.bottom, 10)
            if let n = store.timingNarrative {
                Text(n).font(.system(size: 12)).italic().foregroundStyle(theme.textMuted).lineSpacing(2).padding(.bottom, 12)
            }
            if store.hasTimingData {
                KitColumnChart(columns: data.weeklyData.map { w in
                    KitColumn(label: w.label,
                              parts: Analytics.Week.buckets.map { KitColumnPart(name: $0.label, value: w.count($0.key), color: color($0.key)) },
                              title: "Week of \(w.label) · \(w.total)")
                }, height: 200, labelEvery: data.weeklyData.count > 8 ? 4 : 1,
                   summary: "Completion timing by week. \(store.timingNarrative ?? "")")
            } else {
                AnalyticsEmpty(text: "No completed items with due dates in this period.")
            }
        }
    }

    // ── On-time Rate Trend ──────────────────────────────────────────────────

    private var trend: some View {
        AnalyticsCard(title: "On-time Rate Trend", explain: "Your on-time share, week by week. Higher is better.",
                      subtitle: "Weekly % of tasks & reminders completed on time or early · items with due dates only") {
            KitLineChart(points: data.onTimeRateTrend.map { p in
                KitLinePoint(label: p.label, value: p.rate, detail: p.rate.map { "\($0)% on time (\(p.total) items)" } ?? "No data")
            }, color: theme.green500, percent: true, labelEvery: data.onTimeRateTrend.count > 8 ? 4 : 1,
               summary: "On-time rate by week, as a percentage")
        }
    }

    // ── When You Complete Things ────────────────────────────────────────────

    private var timeOfDay: some View {
        AnalyticsCard(title: "When You Complete Things", explain: "The times of day you usually finish things.",
                      subtitle: "Hour-of-day breakdown · tasks, reminders & routines · \(data.rangeLabel)") {
            if data.hasTodData {
                let bins = data.todData
                KitColumnChart(columns: bins.enumerated().map { i, b in
                    KitColumn(label: b.label, parts: [KitColumnPart(name: "Completions", value: b.count, color: theme.accent)],
                              title: "\(b.label)–\(i < bins.count - 1 ? bins[i + 1].label : "12am")")
                }, height: 160, labelEvery: 1, summary: "Completions by time of day")
            } else {
                AnalyticsEmpty(text: "Not enough data yet for this period.")
            }
        }
    }

    // ── By Priority ─────────────────────────────────────────────────────────

    private var priority: some View {
        let colors = ["high": theme.red500, "medium": theme.orange500, "low": theme.green500, "none": theme.textMuted]
        return AnalyticsCard(title: "By Priority", explain: "The on-time rate for each priority level.",
                             subtitle: "Items with due dates · \(data.rangeLabel)") {
            if store.priorities.isEmpty {
                AnalyticsEmpty(text: "No items with due dates in this period.")
            } else {
                VStack(spacing: 16) {
                    ForEach(store.priorities) { p in
                        VStack(spacing: 6) {
                            HStack(alignment: .top) {
                                HStack(spacing: 8) {
                                    Circle().fill(colors[p.priority] ?? theme.h3).frame(width: 8, height: 8).accessibilityHidden(true)
                                    Text(p.label).font(.system(size: 14)).foregroundStyle(theme.text300)
                                    Text(AnalyticsStore.plural(p.total, "item")).font(.system(size: 12)).foregroundStyle(theme.textMuted)
                                }
                                Spacer(minLength: 8)
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("True on-time: \(p.trueRate.map { "\($0)%" } ?? "—")")
                                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(RateBand(p.trueRate).text(theme))
                                    if let sd = p.sdRate, sd != p.trueRate {
                                        Text("Same-day: \(sd)%").font(.system(size: 12)).foregroundStyle(theme.textMuted)
                                    }
                                }
                            }
                            if let r = p.trueRate { KitRateBar(rate: r) }
                        }
                    }
                }
            }
            if let late = data.lateAgeStats {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Late 8+ days — age at completion (\(AnalyticsStore.plural(late.count, "item")))")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(theme.textMuted)
                    HStack {
                        lateStat("\(String(format: "%g", late.avg))d", "avg")
                        lateStat("\(String(format: "%g", late.median))d", "median")
                        lateStat("\(late.max)d", "longest")
                    }
                }
                .padding(.top, 16)
                .overlay(alignment: .top) { KitDivider() }
                .padding(.top, 20)
            }
        }
    }

    private func lateStat(_ value: String, _ name: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 14, weight: .semibold)).foregroundStyle(theme.red400)
            Text(name).font(.system(size: 10)).foregroundStyle(theme.textMuted)
        }
        .frame(maxWidth: .infinity)
    }

    // ── Activity Heatmap ────────────────────────────────────────────────────

    private var heatmap: some View {
        let h = data.heatmap
        let total = h.weeks.joined().filter { !$0.isFuture }.reduce(0) { $0 + $1.count }
        return AnalyticsCard(title: "Activity Heatmap", explain: "How many things you finished each day. Darker days had more.",
                             subtitle: "All completions (tasks, reminders & routines) · last 12 weeks") {
            KitShadeHeatmap(weeks: h.weeks.map { $0.map { KitShadeCell(intensity: $0.intensity, isFuture: $0.isFuture, tooltip: $0.title) } },
                            dayLabels: h.dayLabels, weekLabels: h.weekLabels,
                            summary: "Activity over the last 12 weeks: \(total) completions")
        }
    }

    // ── Completion Velocity ─────────────────────────────────────────────────

    private var velocity: some View {
        AnalyticsCard(title: "Completion Velocity", explain: "How many things you finished each week, over the last 12 weeks.",
                      subtitle: "Completions per week · last 12 weeks · independent of range toggle") {
            Text(store.velocityLabel).font(.system(size: 12, weight: .medium))
                .foregroundStyle(store.velocityBand == .none ? theme.text400 : store.velocityBand.text(theme))
        } content: {
            if data.hasVelocityData {
                KitLineChart(points: data.velocityData.map { KitLinePoint(label: $0.label, value: $0.count, detail: "\($0.count) completions") },
                             color: theme.accent, labelEvery: data.velocityData.count > 8 ? 2 : 1,
                             summary: "Completions per week, \(store.velocityLabel)")
            } else {
                AnalyticsEmpty(text: "Not enough data yet for this period.")
            }
        }
    }

    // ── Routines Completion Rate ────────────────────────────────────────────

    private var routines: some View {
        let rs = data.routineStats
        return AnalyticsCard(title: "Routines Completion Rate",
                             explain: "The share of each routine's expected days you did it, over the last 30 days.",
                             subtitle: "Last 30 days · active routines · sorted worst to best") {
            if let overall = rs.overallRate {
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(overall)%").font(.system(size: 18, weight: .bold)).foregroundStyle(RateBand(overall).text(theme))
                    Text("\(rs.totalCompleted)/\(rs.totalExpected) days").font(.system(size: 10)).foregroundStyle(theme.textMuted)
                }
                .accessibilityElement(children: .combine)
            }
        } content: {
            if rs.byRoutine.isEmpty {
                AnalyticsEmpty(text: "No active routines.")
            } else {
                VStack(spacing: 16) {
                    ForEach(rs.byRoutine) { routineRow($0) }
                }
                if data.hasRoutineVelData {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Weekly consistency · last 8 weeks (all active routines combined)")
                            .font(.system(size: 12, weight: .medium)).foregroundStyle(theme.textMuted)
                        KitLineChart(points: data.routineVelData.map { w in
                            KitLinePoint(label: w.label, value: w.rate,
                                         detail: w.rate.map { "\($0)% (\(w.completed)/\(w.expected) scheduled days)" } ?? "No data")
                        }, color: theme.accent, percent: true, height: 120, summary: "Weekly routine consistency, as a percentage")
                    }
                    .padding(.top, 16)
                    .overlay(alignment: .top) { KitDivider() }
                    .padding(.top, 20)
                }
            }
        }
    }

    private func routineRow(_ r: Analytics.RoutineStats.Item) -> some View {
        VStack(spacing: 6) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        RoutineLink(title: r.title, id: r.id)
                        Text(AnalyticsStore.frequencyLabel(r.frequency)).font(.system(size: 10)).foregroundStyle(theme.textMuted)
                    }
                    let notes = AnalyticsStore.notes(for: r)
                    if !notes.isEmpty {
                        notes.enumerated().reduce(Text("")) { acc, item in
                            let t = Text(item.element.text).foregroundStyle(noteColor(item.element.tone))
                            let dot = Text("  ·  ").foregroundStyle(theme.border3)
                            return item.offset == 0 ? t : Text("\(acc)\(dot)\(t)")
                        }
                        .font(.system(size: 11))
                    }
                    if let top = AnalyticsStore.topStreakText(r) {
                        Text(top).font(.system(size: 10)).foregroundStyle(theme.textMuted)
                    }
                }
                Spacer(minLength: 8)
                if let rate = r.rate {
                    HStack(spacing: 4) {
                        Text("\(rate)%").font(.system(size: 14, weight: .semibold)).foregroundStyle(RateBand(rate).text(theme))
                        Text("\(r.completed)/\(r.expected)d").font(.system(size: 12)).foregroundStyle(theme.textMuted)
                    }
                } else {
                    Text("—").font(.system(size: 14)).foregroundStyle(theme.textMuted)
                }
            }
            if let rate = r.rate { KitRateBar(rate: rate) }
        }
    }

    private func noteColor(_ tone: AnalyticsStore.RoutineNote.Tone) -> Color {
        switch tone {
        case .streak: theme.amber500
        case .muted: theme.textMuted
        case .faint: theme.textMuted.opacity(0.8)
        case .broke: theme.red400.opacity(0.85)
        case .rate(let band): band.text(theme)
        }
    }
}

/// A routine's name; a click opens it in Routines
private struct RoutineLink: View {
    @Environment(MacRouter.self) private var router
    let title: String
    let id: Int

    var body: some View {
        KitLinkButton(title: title, size: 14, tone: .muted) { router.open(.routine(id)) }
            .help("Open routine")
            .contextMenu { Button("Open Routine") { router.open(.routine(id)) } }
    }
}
