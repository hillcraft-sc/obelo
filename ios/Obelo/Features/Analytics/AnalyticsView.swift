import Charts
import SwiftUI

// Analytics — views/analytics/index.ejs, from the same computeAnalytics() the web page uses.
// Chart colours follow the web's Chart.js setup; tap or drag a chart to inspect a week/hour.

extension Analytics.Finding {
    /// The app screen for href
    var route: Route? {
        guard let t = target else { return nil }
        guard let id = t.id else { return .module(t.module) }
        switch t.module {
        case "tasks": return .task(id)
        case "reminders": return .reminder(id)
        case "routines": return .routine(id)
        default: return .note(id)
        }
    }
}

/// Timing buckets in stacking order, with the web's colours (accent = "on time"). The late
/// shades were re-picked with the dataviz palette validator so 4–7d and 8+d stay distinguishable.
private let buckets: [(key: String, label: String, hex: String?)] = [
    ("early", "Early", "#22c55e"), ("on_time", "On time", nil), ("late_same_day", "Same-day late", "#facc15"),
    ("late_1_3", "Late 1–3d", "#f97316"), ("late_4_7", "Late 4–7d", "#9a3412"), ("late_8plus", "Late 8+d", "#ef4444"),
]

private func rateColor(_ r: Int?, _ theme: Theme) -> Color {
    guard let r else { return theme.textMuted }
    return r >= 80 ? theme.green400 : r >= 50 ? theme.amber400 : theme.red400
}

private func rateFill(_ r: Int, _ theme: Theme) -> Color {
    r >= 80 ? theme.green500 : r >= 50 ? theme.amber500 : theme.red500
}

struct AnalyticsView: View {
    @Environment(AppState.self) private var app
    @Environment(\.theme) private var theme
    @State private var range = "30"
    @State private var data: Analytics?
    @State private var error: String?

    var body: some View {
        Page(maxWidth: 896, refresh: load) {
            PageHeader(title: "Analytics", subtitle: "When you finish tasks, reminders and routines, compared with when they were due.", pageName: true)
            rangePicker
            if let error { Banner(kind: .error, text: error) }
            if let d = data {
                if let findings = d.standsOut, !findings.isEmpty { standsOut(findings, byAi: d.standsOutByAi == true) }
                if d.summary.total > 0 && d.summary.total < 5 {
                    Card(padding: 14) {
                        Label("Analytics improve with more data — you have \(d.summary.total) completion\(d.summary.total == 1 ? "" : "s") in this period.", systemImage: "info.circle")
                            .font(.system(size: 12)).foregroundStyle(theme.textMuted)
                    }
                }
                summary(d)
                TimingChart(data: d)
                if d.hasOnTimeRateTrend { OnTimeTrendChart(points: d.onTimeRateTrend) }
                TimeOfDayChart(data: d)
                priority(d)
                ActivityHeatmap(heatmap: d.heatmap)
                VelocityChart(data: d)
                routines(d)
            } else if error == nil {
                ProgressView().frame(maxWidth: .infinity).padding(40)
            }
        }
        .task(id: "\(range)|\(app.dataVersion)") { await load() }
    }

    private func load() async {
        do {
            let d: Analytics = try await APIClient.shared.get("/analytics", query: ["range": range])
            withAnimation(.easeOut(duration: 0.2)) { data = d }
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    /// The web's segmented 30d / 90d / All time control
    private var rangePicker: some View {
        HStack(spacing: 4) {
            ForEach([("30", "30d"), ("90", "90d"), ("all", "All time")], id: \.0) { value, label in
                Button { range = value } label: {
                    Text(label).font(.system(size: 12, weight: .medium))
                        .foregroundStyle(range == value ? theme.textPrimary : theme.textMuted)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(range == value ? theme.elevated : .clear, in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.border1, lineWidth: 1))
    }

    // ── What stands out ──────────────────────────────────────────────────────

    /// A few plain findings, warnings first; each opens the items behind it
    private func standsOut(_ findings: [Analytics.Finding], byAi: Bool) -> some View {
        Card(padding: 20) {
            VStack(alignment: .leading, spacing: 2) {
                Text("What stands out").font(.system(size: 14, weight: .semibold)).foregroundStyle(theme.textPrimary)
                Text("A few findings from your own data." + (byAi ? " Worded by AI." : ""))
                    .font(.system(size: 12)).foregroundStyle(theme.textMuted)
            }
            .padding(.bottom, 10)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(findings, id: \.self) { f in
                    if let route = f.route {
                        NavigationLink(value: route) { findingRow(f, linked: true) }.buttonStyle(.plain)
                    } else {
                        findingRow(f, linked: false)
                    }
                }
            }
        }
    }

    private func findingRow(_ f: Analytics.Finding, linked: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Circle()
                .fill(f.tone == "good" ? theme.green400 : f.tone == "warn" ? theme.amber400 : theme.textMuted)
                .frame(width: 7, height: 7)
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                .accessibilityHidden(true)
            Text(f.text).font(.system(size: 14)).foregroundStyle(linked ? theme.text300 : theme.text400)
                .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if linked {
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(theme.textMuted)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel((f.tone == "warn" ? "Needs attention: " : f.tone == "good" ? "Going well: " : "") + f.text)
    }

    // ── Summary tiles ────────────────────────────────────────────────────────

    private func summary(_ d: Analytics) -> some View {
        let s = d.summary
        return VStack(spacing: 12) {
            HStack(spacing: 12) {
                heroTile(title: "True on-time rate", rate: s.trueOnTimeRate,
                         note: s.trueOnTimeRate == nil ? "No items with due dates yet." : "within 30 min of due time · \(s.withDueCount) item\(s.withDueCount == 1 ? "" : "s")",
                         hero: true)
                heroTile(title: "Same-day rate", rate: s.sameDayRate,
                         note: s.sameDayRate == nil ? "No items with due dates yet." : "completed on the due day", hero: false)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                statTile("Completed", "\(s.total)", d.rangeLabel, theme.text300)
                statTile("Avg days late", s.avgDaysLate.map { String(format: "%g", $0) } ?? "—",
                         s.avgDaysLate == nil ? "none late" : "days (when late)", s.avgDaysLate == nil ? theme.textMuted : theme.amber500)
                statTile("Best day", s.topDay ?? "—", s.topDay == nil ? "no data yet" : "\(s.topDayCount) completions", theme.text300, small: true)
                statTile("Current streak", "\(d.streak.current)", d.streak.current > 0 ? "day\(d.streak.current == 1 ? "" : "s") in a row" : "no recent completions",
                         d.streak.current > 0 ? theme.accentText : theme.textMuted)
                statTile("Best streak", d.streak.best > 0 ? "\(d.streak.best)" : "—", "days · all time", d.streak.best > 0 ? theme.accentText : theme.textMuted)
            }
        }
    }

    private func heroTile(title: String, rate: Int?, note: String, hero: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 12, weight: hero ? .medium : .regular)).foregroundStyle(hero ? theme.text400 : theme.textMuted)
            Text(rate.map { "\($0)%" } ?? "—")
                .font(.system(size: hero ? 36 : 30, weight: .bold))
                .foregroundStyle(rateColor(rate, theme))
                .contentTransition(.numericText())
            Text(note).font(.system(size: 12)).foregroundStyle(theme.textMuted).lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(hero ? theme.accentHover : theme.border1, lineWidth: 1))
    }

    private func statTile(_ title: String, _ value: String, _ note: String, _ color: Color, small: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 11)).foregroundStyle(theme.textMuted)
            Text(value).font(.system(size: small ? 16 : 20, weight: .semibold)).foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.7)
            Text(note).font(.system(size: 11)).foregroundStyle(theme.textMuted).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12).padding(.vertical, 12)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(theme.border1, lineWidth: 1))
    }

    // ── By priority ──────────────────────────────────────────────────────────

    private func priority(_ d: Analytics) -> some View {
        let colors = ["high": theme.red500, "medium": theme.orange500, "low": theme.green500, "none": theme.textMuted]
        let rows = d.priorityData.filter { $0.total > 0 }
        return ChartCard(title: "By Priority", explain: "The on-time rate for each priority level.", subtitle: "Items with due dates · \(d.rangeLabel)") {
            if rows.isEmpty {
                ChartEmpty(text: "No items with due dates in this period.")
            } else {
                VStack(spacing: 16) {
                    ForEach(rows) { p in
                        VStack(spacing: 6) {
                            HStack(alignment: .top) {
                                HStack(spacing: 8) {
                                    Dot(color: colors[p.priority] ?? theme.h3)
                                    Text(p.label).font(.system(size: 14)).foregroundStyle(theme.text300)
                                    Text("\(p.total) item\(p.total == 1 ? "" : "s")").font(.system(size: 12)).foregroundStyle(theme.textMuted)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("True on-time: \(p.trueRate ?? 0)%").font(.system(size: 14, weight: .semibold)).foregroundStyle(rateColor(p.trueRate, theme))
                                    if let sd = p.sdRate, sd != p.trueRate {
                                        Text("Same-day: \(sd)%").font(.system(size: 12)).foregroundStyle(theme.textMuted)
                                    }
                                }
                            }
                            RateBar(rate: p.trueRate ?? 0)
                        }
                    }
                }
                if let late = d.lateAgeStats {
                    RowDivider().padding(.top, 16)
                    Text("Late 8+ days — age at completion (\(late.count) item\(late.count == 1 ? "" : "s"))")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(theme.textMuted).padding(.top, 12)
                    HStack {
                        ForEach([("avg", String(format: "%gd", late.avg)), ("median", String(format: "%gd", late.median)), ("longest", "\(late.max)d")], id: \.0) { label, value in
                            VStack(spacing: 2) {
                                Text(value).font(.system(size: 14, weight: .semibold)).foregroundStyle(theme.red400)
                                Text(label).font(.system(size: 10)).foregroundStyle(theme.textMuted)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.top, 8)
                }
            }
        }
    }

    // ── Routines ─────────────────────────────────────────────────────────────

    private func routines(_ d: Analytics) -> some View {
        let rs = d.routineStats
        return Card(padding: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Routines Completion Rate").font(.system(size: 14, weight: .semibold)).foregroundStyle(theme.textPrimary)
                    Text("The share of each routine's expected days you did it, over the last 30 days.")
                        .font(.system(size: 13)).foregroundStyle(theme.text400).padding(.vertical, 2)
                    Text("Last 30 days · active routines · sorted worst to best").font(.system(size: 12)).foregroundStyle(theme.textMuted)
                }
                Spacer()
                if let overall = rs.overallRate {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("\(overall)%").font(.system(size: 18, weight: .bold)).foregroundStyle(rateColor(overall, theme))
                        Text("\(rs.totalCompleted)/\(rs.totalExpected) days").font(.system(size: 10)).foregroundStyle(theme.textMuted)
                    }
                }
            }
            .padding(.bottom, 16)
            if rs.byRoutine.isEmpty {
                ChartEmpty(text: "No active routines.")
            } else {
                VStack(spacing: 16) {
                    ForEach(rs.byRoutine) { r in routineRow(r) }
                }
                if d.hasRoutineVelData {
                    RowDivider().padding(.top, 20)
                    Text("Weekly consistency · last 8 weeks (all active routines combined)")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(theme.textMuted).padding(.vertical, 12)
                    RoutineConsistencyChart(weeks: d.routineVelData)
                }
            }
        }
    }

    private func routineRow(_ r: Analytics.RoutineStats.Item) -> some View {
        var notes: [Text] = []
        if r.streakCurrent > 0 {
            notes.append(Text("🔥 \(r.streakCurrent)d streak\(r.streakBest > r.streakCurrent ? " · best \(r.streakBest)d" : "")").foregroundStyle(theme.amber500))
        } else if r.streakBest > 0 {
            notes.append(Text("best \(r.streakBest)d").foregroundStyle(theme.textMuted))
        }
        if r.streakCount > 0 {
            notes.append(Text("\(r.streakCount) streak\(r.streakCount == 1 ? "" : "s") · avg \(r.streakAvg)d").foregroundStyle(theme.textMuted))
        }
        if r.streakCurrent == 0, let b = r.lastBroken {
            notes.append(Text("broke \(b.length)d · \(Fmt.shortDay(String(b.endDate.prefix(10))))").foregroundStyle(theme.red400.opacity(0.8)))
        }
        if let t = r.specificTime, let rate = r.specificTimeRate {
            notes.append(Text("on time at \(t): \(rate)%\(r.timedSampleSize < 5 ? " (\(r.timedSampleSize) logged)" : "")").foregroundStyle(rateColor(rate, theme)))
        }
        let line = notes.enumerated().reduce(Text("")) { acc, item in
            item.offset == 0 ? item.element : Text("\(acc)\(Text(" · ").foregroundStyle(theme.textMuted))\(item.element)")
        }
        return VStack(spacing: 6) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        NavigationLink(value: Route.routine(r.id)) {
                            Text(r.title).font(.system(size: 14)).foregroundStyle(theme.text300).lineLimit(1)
                        }
                        .buttonStyle(.plain)
                        Text(Fmt.freqLabels[r.frequency] ?? r.frequency).font(.system(size: 10)).foregroundStyle(theme.textMuted)
                    }
                    if !notes.isEmpty { line.font(.system(size: 10)) }
                    if let top = AnalyticsStore.topStreakText(r) {
                        Text(top).font(.system(size: 9)).foregroundStyle(theme.textMuted)
                    }
                }
                Spacer()
                if let rate = r.rate {
                    HStack(spacing: 4) {
                        Text("\(rate)%").font(.system(size: 14, weight: .semibold)).foregroundStyle(rateColor(rate, theme))
                        Text("\(r.completed)/\(r.expected)d").font(.system(size: 12)).foregroundStyle(theme.textMuted)
                    }
                } else {
                    Text("—").font(.system(size: 14)).foregroundStyle(theme.textMuted)
                }
            }
            if let rate = r.rate { RateBar(rate: rate) }
        }
    }
}

// ── Building blocks ──────────────────────────────────────────────────────────

/// "bg-gray-900 border rounded-xl p-5" with an h2 + caption, like each web chart card
private struct ChartCard<Trailing: View, Content: View>: View {
    @Environment(\.theme) private var theme
    let title: String
    /// What the chart shows, in plain words (the web's explanation line)
    var explain: String? = nil
    let subtitle: String
    @ViewBuilder var trailing: Trailing
    @ViewBuilder var content: Content

    var body: some View {
        Card(padding: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(theme.textPrimary)
                    if let explain {
                        Text(explain).font(.system(size: 13)).foregroundStyle(theme.text400).padding(.vertical, 2)
                    }
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(theme.textMuted)
                }
                Spacer()
                trailing
            }
            .padding(.bottom, 12)
            content
        }
    }
}

extension ChartCard where Trailing == EmptyView {
    init(title: String, explain: String? = nil, subtitle: String, @ViewBuilder content: () -> Content) {
        self.init(title: title, explain: explain, subtitle: subtitle, trailing: { EmptyView() }, content: content)
    }
}

private struct ChartEmpty: View {
    @Environment(\.theme) private var theme
    let text: String
    var body: some View {
        Text(text).font(.system(size: 14)).foregroundStyle(theme.textMuted)
            .frame(maxWidth: .infinity, minHeight: 96)
    }
}

private struct RateBar: View {
    @Environment(\.theme) private var theme
    let rate: Int
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(theme.h2)
                Capsule().fill(rateFill(rate, theme)).frame(width: geo.size.width * CGFloat(min(100, max(0, rate))) / 100)
            }
        }
        .frame(height: 5)
        .accessibilityLabel("\(rate) percent")
    }
}

/// Shared axis styling: recessive grid in the theme's border colour, muted 11pt ticks
private struct ThemedAxes: ViewModifier {
    @Environment(\.theme) private var theme
    var percent = false
    var labelEvery = 1
    @ViewBuilder func body(content: Content) -> some View {
        let styled = content
            .chartXAxis {
                AxisMarks { value in
                    AxisGridLine().foregroundStyle(theme.border1)
                    if value.index % labelEvery == 0 {
                        AxisValueLabel().font(.system(size: 10)).foregroundStyle(theme.textMuted)
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: percent ? .stride(by: 25) : .automatic(desiredCount: 4)) { value in
                    AxisGridLine().foregroundStyle(theme.border1)
                    AxisValueLabel {
                        if let v = value.as(Int.self) { Text(percent ? "\(v)%" : "\(v)") }
                    }
                    .font(.system(size: 10)).foregroundStyle(theme.textMuted)
                }
            }
        if percent { styled.chartYScale(domain: 0...100) } else { styled }
    }
}

/// Small callout shown above a selected bar/point
private struct Callout: View {
    @Environment(\.theme) private var theme
    let title: String
    let lines: [(String, Color?)]
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(theme.text100)
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                HStack(spacing: 5) {
                    if let c = line.1 { RoundedRectangle(cornerRadius: 2).fill(c).frame(width: 8, height: 8) }
                    Text(line.0).font(.system(size: 11)).foregroundStyle(theme.text300)
                }
            }
        }
        .padding(8)
        .background(theme.elevated, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.border2, lineWidth: 1))
        .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
    }
}

// ── Charts ───────────────────────────────────────────────────────────────────

private struct TimingChart: View {
    @Environment(\.theme) private var theme
    let data: Analytics
    @State private var selected: String?

    /// Bucket colours follow the theme's status palette (Catppuccin's in those themes)
    private func color(_ hex: String?) -> Color {
        switch hex {
        case nil: theme.accent
        case "#22c55e": theme.green500
        case "#facc15": theme.yellow400
        case "#f97316": theme.orange500
        case "#9a3412": theme.orange800
        case "#ef4444": theme.red500
        case let hex?: Color(hex: hex)
        }
    }

    private var narrative: String? {
        let w = data.weeklyData
        let n = w.reduce(0) { $0 + $1.total }
        guard n > 0 else { return nil }
        let onTime = w.reduce(0) { $0 + $1.early + $1.on_time }
        let sdLate = w.reduce(0) { $0 + $1.late_same_day }
        let daysLate = n - onTime - sdLate
        let all = n == 1 ? "Your one completion was" : n == 2 ? "Both completions were" : "All \(n) completions were"
        let pct = { (x: Int) in Int((Double(x) / Double(n) * 100).rounded()) }
        let items = { (x: Int) in "\(x) \(x == 1 ? "item was" : "items were")" }
        if onTime == n { return "\(all) on time or early this period." }
        if sdLate == n { return "\(all) same-day late — you hit the right day but missed the due time by more than 30 minutes." }
        if daysLate == n { return "\(all) finished days after the due date." }
        if onTime >= sdLate && onTime >= daysLate {
            return "\(pct(onTime))% of completions were on time or early (\(onTime) of \(n))." + (daysLate > 0 ? " \(items(daysLate)) days late." : "")
        }
        if sdLate >= daysLate {
            return "\(pct(sdLate))% of completions were same-day late — right day, but past the due time." + (daysLate > 0 ? " \(items(daysLate)) days late." : "")
        }
        return "\(pct(daysLate))% of completions were finished days after their due date (\(daysLate) of \(n))." + (onTime > 0 ? " \(items(onTime)) on time or early." : "")
    }

    var body: some View {
        ChartCard(title: "Completion Timing", explain: "When you finished things compared with when they were due: early, on time, or late.", subtitle: "Items with due dates · \(data.rangeLabel) · 30-min grace window") {
            FlowLayout(spacing: 12) {
                ForEach(buckets, id: \.key) { b in
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 2).fill(color(b.hex)).frame(width: 10, height: 10)
                        Text(b.label).font(.system(size: 12)).foregroundStyle(theme.textMuted)
                    }
                }
            }
            .padding(.bottom, 10)
            if let narrative {
                Text(narrative).font(.system(size: 12)).italic().foregroundStyle(theme.textMuted).lineSpacing(2).padding(.bottom, 12)
            }
            if data.weeklyData.contains(where: { $0.total > 0 }) {
                Chart {
                    ForEach(data.weeklyData) { week in
                        ForEach(buckets, id: \.key) { b in
                            let v = week.count(b.key)
                            if v > 0 {
                                BarMark(x: .value("Week", week.label), y: .value("Items", v), width: .ratio(0.6))
                                    .foregroundStyle(color(b.hex))
                                    .opacity(selected == nil || selected == week.label ? 1 : 0.35)
                            }
                        }
                    }
                    if let selected, let week = data.weeklyData.first(where: { $0.label == selected }) {
                        RuleMark(x: .value("Week", selected))
                            .foregroundStyle(.clear)
                            .annotation(position: .top, spacing: 4, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                                Callout(title: "Week of \(week.label) · \(week.total)",
                                        lines: buckets.compactMap { b in week.count(b.key) > 0 ? ("\(b.label): \(week.count(b.key))", color(b.hex)) : nil })
                            }
                    }
                }
                .chartXSelection(value: $selected)
                .modifier(ThemedAxes(labelEvery: data.weeklyData.count > 8 ? 4 : 1))
                .frame(height: 200)
                .accessibilityLabel("Completion timing by week")
            } else {
                ChartEmpty(text: "No completed items with due dates in this period.")
            }
        }
    }
}

private struct OnTimeTrendChart: View {
    @Environment(\.theme) private var theme
    let points: [Analytics.RatePoint]
    @State private var selected: String?

    var body: some View {
        ChartCard(title: "On-time Rate Trend", explain: "Your on-time share, week by week. Higher is better.", subtitle: "Weekly % of tasks & reminders completed on time or early · items with due dates only") {
            Chart {
                ForEach(points.filter { $0.rate != nil }) { p in
                    AreaMark(x: .value("Week", p.label), y: .value("Rate", p.rate ?? 0))
                        .foregroundStyle(theme.green500.opacity(0.1))
                        .interpolationMethod(.catmullRom)
                    LineMark(x: .value("Week", p.label), y: .value("Rate", p.rate ?? 0))
                        .foregroundStyle(theme.green500)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .interpolationMethod(.catmullRom)
                    PointMark(x: .value("Week", p.label), y: .value("Rate", p.rate ?? 0))
                        .foregroundStyle(theme.green500).symbolSize(selected == p.label ? 80 : 30)
                }
                if let selected, let p = points.first(where: { $0.label == selected }) {
                    RuleMark(x: .value("Week", selected)).foregroundStyle(theme.border3)
                        .annotation(position: .top, spacing: 4, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                            Callout(title: "Week of \(p.label)", lines: [(p.rate.map { "\($0)% on time (\(p.total) items)" } ?? "No data", nil)])
                        }
                }
            }
            .chartXSelection(value: $selected)
            .modifier(ThemedAxes(percent: true, labelEvery: points.count > 8 ? 4 : 1))
            .frame(height: 160)
        }
    }
}

private struct TimeOfDayChart: View {
    @Environment(\.theme) private var theme
    let data: Analytics
    @State private var selected: String?

    var body: some View {
        ChartCard(title: "When You Complete Things", explain: "The times of day you usually finish things.", subtitle: "Hour-of-day breakdown · tasks, reminders & routines · \(data.rangeLabel)") {
            if data.hasTodData {
                Chart {
                    ForEach(data.todData) { b in
                        BarMark(x: .value("Time", b.label), y: .value("Completions", b.count), width: .ratio(0.7))
                            .foregroundStyle(theme.accent)
                            .opacity(selected == nil || selected == b.label ? 1 : 0.35)
                    }
                    if let selected, let i = data.todData.firstIndex(where: { $0.label == selected }) {
                        let next = i < data.todData.count - 1 ? data.todData[i + 1].label : "12am"
                        RuleMark(x: .value("Time", selected)).foregroundStyle(.clear)
                            .annotation(position: .top, spacing: 4, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                                Callout(title: "\(selected)–\(next)", lines: [("\(data.todData[i].count) completions", nil)])
                            }
                    }
                }
                .chartXSelection(value: $selected)
                .modifier(ThemedAxes(labelEvery: 2))
                .frame(height: 160)
            } else {
                ChartEmpty(text: "Not enough data yet for this period.")
            }
        }
    }
}

private struct VelocityChart: View {
    @Environment(\.theme) private var theme
    let data: Analytics
    @State private var selected: String?

    var body: some View {
        let trend = data.velocityTrend
        ChartCard(title: "Completion Velocity", explain: "How many things you finished each week, over the last 12 weeks.", subtitle: "Completions per week · last 12 weeks · independent of range toggle") {
            Text(trend == "up" ? "↑ trending up" : trend == "down" ? "↓ trending down" : "→ steady")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(trend == "up" ? theme.green400 : trend == "down" ? theme.red400 : theme.text400)
        } content: {
            if data.hasVelocityData {
                Chart {
                    ForEach(data.velocityData) { w in
                        AreaMark(x: .value("Week", w.label), y: .value("Completions", w.count))
                            .foregroundStyle(theme.accent.opacity(0.15)).interpolationMethod(.catmullRom)
                        LineMark(x: .value("Week", w.label), y: .value("Completions", w.count))
                            .foregroundStyle(theme.accent).lineStyle(StrokeStyle(lineWidth: 2)).interpolationMethod(.catmullRom)
                        PointMark(x: .value("Week", w.label), y: .value("Completions", w.count))
                            .foregroundStyle(theme.accent).symbolSize(selected == w.label ? 80 : 30)
                    }
                    if let selected, let w = data.velocityData.first(where: { $0.label == selected }) {
                        RuleMark(x: .value("Week", selected)).foregroundStyle(theme.border3)
                            .annotation(position: .top, spacing: 4, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                                Callout(title: "Week of \(w.label)", lines: [("\(w.count) completions", nil)])
                            }
                    }
                }
                .chartXSelection(value: $selected)
                .modifier(ThemedAxes(labelEvery: 4))
                .frame(height: 160)
            } else {
                ChartEmpty(text: "Not enough data yet for this period.")
            }
        }
    }
}

private struct RoutineConsistencyChart: View {
    @Environment(\.theme) private var theme
    let weeks: [Analytics.RoutineWeek]
    @State private var selected: String?

    var body: some View {
        Chart {
            ForEach(weeks.filter { $0.rate != nil }) { w in
                AreaMark(x: .value("Week", w.label), y: .value("Rate", w.rate ?? 0))
                    .foregroundStyle(theme.accent.opacity(0.15)).interpolationMethod(.catmullRom)
                LineMark(x: .value("Week", w.label), y: .value("Rate", w.rate ?? 0))
                    .foregroundStyle(theme.accent).lineStyle(StrokeStyle(lineWidth: 2)).interpolationMethod(.catmullRom)
                PointMark(x: .value("Week", w.label), y: .value("Rate", w.rate ?? 0))
                    .foregroundStyle(theme.accent).symbolSize(selected == w.label ? 80 : 30)
            }
            if let selected, let w = weeks.first(where: { $0.label == selected }) {
                RuleMark(x: .value("Week", selected)).foregroundStyle(theme.border3)
                    .annotation(position: .top, spacing: 4, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        Callout(title: "Week of \(w.label)",
                                lines: [(w.rate.map { "\($0)% (\(w.completed)/\(w.expected) scheduled days)" } ?? "No data", nil)])
                    }
            }
        }
        .chartXSelection(value: $selected)
        .modifier(ThemedAxes(percent: true, labelEvery: 2))
        .frame(height: 120)
    }
}

/// 12-week activity grid: accent at 0.2 / 0.45 / 0.7 / 1 opacity by intensity, like .heat-1…4
private struct ActivityHeatmap: View {
    @Environment(\.theme) private var theme
    let heatmap: Analytics.Heatmap
    @State private var selected: Analytics.Heatmap.Cell?

    private func fill(_ cell: Analytics.Heatmap.Cell) -> Color {
        if cell.isFuture { return theme.elevated.opacity(0.35) }
        return switch cell.intensity {
        case 1: theme.accent.opacity(0.2)
        case 2: theme.accent.opacity(0.45)
        case 3: theme.accent.opacity(0.7)
        case 4: theme.accent
        default: theme.elevated
        }
    }

    var body: some View {
        ChartCard(title: "Activity Heatmap", explain: "How many things you finished each day. Darker days had more.", subtitle: "All completions (tasks, reminders & routines) · last 12 weeks") {
            HStack(alignment: .top, spacing: 6) {
                VStack(alignment: .trailing, spacing: 4) {
                    Color.clear.frame(height: 12)
                    ForEach(Array(heatmap.dayLabels.enumerated()), id: \.offset) { i, d in
                        Text(i % 2 == 1 ? d : " ").font(.system(size: 9)).foregroundStyle(theme.textMuted).frame(height: 16)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        ForEach(Array(heatmap.weekLabels.enumerated()), id: \.offset) { i, label in
                            Text(i % 4 == 0 ? label : " ").font(.system(size: 9)).foregroundStyle(theme.textMuted)
                                .fixedSize().frame(width: 16, height: 12, alignment: .leading)
                        }
                    }
                    HStack(spacing: 4) {
                        ForEach(Array(heatmap.weeks.enumerated()), id: \.offset) { _, week in
                            VStack(spacing: 4) {
                                ForEach(week, id: \.dateStr) { cell in
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(fill(cell))
                                        .overlay(RoundedRectangle(cornerRadius: 3).stroke(selected == cell ? theme.textPrimary : .clear, lineWidth: 1.5))
                                        .frame(width: 16, height: 16)
                                        .onTapGesture { selected = selected == cell ? nil : cell }
                                        .accessibilityLabel(cell.title)
                                }
                            }
                        }
                    }
                }
            }
            HStack(spacing: 6) {
                Text("Less").font(.system(size: 10)).foregroundStyle(theme.textMuted)
                ForEach(0..<5) { i in
                    RoundedRectangle(cornerRadius: 3).fill(i == 0 ? theme.elevated : theme.accent.opacity([0, 0.2, 0.45, 0.7, 1][i])).frame(width: 12, height: 12)
                }
                Text("More").font(.system(size: 10)).foregroundStyle(theme.textMuted)
                Spacer()
                if let selected {
                    Text(selected.title).font(.system(size: 11, weight: .medium)).foregroundStyle(theme.text300)
                }
            }
            .padding(.top, 12)
        }
    }
}
