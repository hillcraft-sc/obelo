import AppIntents
import SwiftUI
import WidgetKit

// "Today" widget: the same data as the app's Today page (GET /api/v1/dashboard), in the
// user's theme. Small: what's due + next focus task. Medium: up to four items with tick-off
// buttons. Large: focus, due & overdue, next events and routine progress. Lock screen: a
// one-line summary. Tapping an item opens it in the app (obelo://open/…).

#if WIDGET_EXTENSION
@main
struct ObeloWidgets: WidgetBundle {
    var body: some Widget { TodayWidget() }
}
#endif

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "today", provider: TodayProvider()) { entry in
            TodayWidgetView(entry: entry)
        }
        .configurationDisplayName("Today")
        .description("Your focus tasks, what's due and today's routines.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular])
    }
}

// ── Data ─────────────────────────────────────────────────────────────────────

struct TodayEntry: TimelineEntry {
    enum State { case ok(Dashboard), signedOut, failed }
    let date: Date
    let state: State
    let appearance: Appearance?
}

struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry {
        TodayEntry(date: .now, state: .ok(.sample), appearance: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        if context.isPreview { completion(placeholder(in: context)); return }
        Task { completion(await Self.load()) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        Task {
            let entry = await Self.load()
            // The app also reloads the widget whenever you change something
            // Every 30 minutes, and just after midnight so a new day shows at once (issue #8)
            let soon = Date.now.addingTimeInterval(30 * 60)
            let cal = Calendar.current
            let midnight = cal.date(byAdding: .minute, value: 1, to: cal.startOfDay(for: cal.date(byAdding: .day, value: 1, to: .now) ?? soon)) ?? soon
            completion(Timeline(entries: [entry], policy: .after(min(soon, midnight))))
        }
    }

    static func load() async -> TodayEntry {
        let appearance = AppGroup.appearance
        do {
            let d: Dashboard = try await APIClient.shared.get("/dashboard")
            return TodayEntry(date: .now, state: .ok(d), appearance: appearance)
        } catch APIError.unauthorized {
            return TodayEntry(date: .now, state: .signedOut, appearance: appearance)
        } catch {
            return TodayEntry(date: .now, state: .failed, appearance: appearance)
        }
    }
}

// ── Tick-off button ──────────────────────────────────────────────────────────

struct CompleteItemIntent: AppIntent {
    static let title: LocalizedStringResource = "Complete item"
    static let isDiscoverable = false

    @Parameter(title: "Kind") var kind: String
    @Parameter(title: "ID") var id: Int

    init() {}
    init(kind: String, id: Int) { self.kind = kind; self.id = id }

    func perform() async throws -> some IntentResult {
        let path = kind == "reminder" ? "/reminders/\(id)/complete" : kind == "routine" ? "/routines/\(id)/complete" : "/tasks/\(id)/complete"
        try await APIClient.shared.post(path)
        return .result() // WidgetKit reloads the timeline after an intent runs
    }
}

// ── Views ────────────────────────────────────────────────────────────────────

struct TodayWidgetView: View {
    @Environment(\.widgetFamily) private var widgetFamily
    let entry: TodayEntry
    /// Debug builds of the app render the widget at each size (`-route widget`)
    var familyOverride: WidgetFamily? = nil
    private var family: WidgetFamily { familyOverride ?? widgetFamily }

    private var theme: Theme { Theme.resolve(entry.appearance) }

    var body: some View {
        Group {
            switch entry.state {
            case .ok(let d): content(d)
            case .signedOut: message("Open Obelo to sign in")
            case .failed: message("Couldn't reach Obelo")
            }
        }
        .environment(\.theme, theme)
        .containerBackground(for: .widget) { theme.surface }
    }

    @ViewBuilder private func content(_ d: Dashboard) -> some View {
        switch family {
        case .systemSmall: SmallView(d: d)
        case .systemMedium: ListView(d: d, maxRows: 4, compactHeader: true)
        case .accessoryRectangular: LockView(d: d)
        default: LargeView(d: d)
        }
    }

    private func message(_ text: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "checkmark.circle").font(.title2).foregroundStyle(theme.accentText)
            Text(text).font(.system(size: 13, weight: .medium)).foregroundStyle(theme.text300).multilineTextAlignment(.center)
        }
        .widgetURL(URL(string: "obelo://open/today"))
    }
}

/// One tickable line: focus task, due task or reminder
private struct Row: Identifiable {
    let id: String
    let kind: String     // task | reminder
    let itemID: Int
    let title: String
    let detail: String
    let overdue: Bool
    let dueToday: Bool
    let priority: String
}

private func rows(_ d: Dashboard) -> [Row] {
    var seen = Set<Int>()
    var result: [Row] = []
    for t in d.focusTasks where seen.insert(t.id).inserted {
        result.append(Row(id: "t\(t.id)", kind: "task", itemID: t.id, title: t.title,
                          detail: Fmt.time(t.dueTime, hour12: true), overdue: t.dueState == "overdue", dueToday: false, priority: t.priority))
    }
    for e in d.due {
        if let t = e.task, seen.insert(t.id).inserted {
            result.append(Row(id: "t\(t.id)", kind: "task", itemID: t.id, title: t.title,
                              detail: Fmt.due(t.dueDate, t.dueTime, hour12: true), overdue: e.overdue, dueToday: !e.overdue, priority: t.priority))
        } else if let r = e.reminder {
            result.append(Row(id: "r\(r.id)", kind: "reminder", itemID: r.id, title: r.title,
                              detail: Fmt.due(r.dueDate, r.dueTime, hour12: true), overdue: e.overdue, dueToday: !e.overdue, priority: r.priority))
        }
    }
    return result
}

private struct Header: View {
    @Environment(\.theme) private var theme
    let d: Dashboard
    var compact = false

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(Date.now.formatted(.dateTime.weekday(compact ? .abbreviated : .wide).month(.abbreviated).day()))
                .font(.system(size: compact ? 13 : 15, weight: .bold)).foregroundStyle(theme.textPrimary)
            Spacer()
            let overdue = d.due.filter(\.overdue).count
            if overdue > 0 {
                Text("\(overdue) overdue").font(.system(size: 11, weight: .semibold)).foregroundStyle(theme.red400)
            } else if !d.routines.isEmpty {
                Text("\(d.routines.filter(\.completedToday).count)/\(d.routines.count) routines")
                    .font(.system(size: 11)).foregroundStyle(theme.textMuted)
            }
        }
    }
}

private struct ItemRow: View {
    @Environment(\.theme) private var theme
    let row: Row

    var body: some View {
        HStack(spacing: 8) {
            Button(intent: CompleteItemIntent(kind: row.kind, id: row.itemID)) {
                Circle().stroke(row.overdue ? theme.red500 : theme.border3, lineWidth: 1.5).frame(width: 16, height: 16)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Complete \(row.title)")
            Link(destination: URL(string: "obelo://open/\(row.kind)/\(row.itemID)")!) {
                HStack(spacing: 6) {
                    if row.kind == "reminder" {
                        Image(systemName: "bell").font(.system(size: 9)).foregroundStyle(row.overdue ? theme.red500 : theme.textMuted)
                    } else {
                        Circle().fill(theme.priorityDot(row.priority)).frame(width: 6, height: 6)
                    }
                    Text(row.title).font(.system(size: 13)).foregroundStyle(theme.text200).lineLimit(1)
                    Spacer(minLength: 4)
                    if !row.detail.isEmpty {
                        Text(row.detail).font(.system(size: 11))
                            .foregroundStyle(row.overdue ? theme.red400 : row.dueToday ? theme.green400 : theme.textMuted)
                            .lineLimit(1)
                    }
                }
            }
        }
    }
}

private struct SmallView: View {
    @Environment(\.theme) private var theme
    let d: Dashboard

    var body: some View {
        let dueCount = d.due.count
        let overdue = d.due.filter(\.overdue).count
        VStack(alignment: .leading, spacing: 4) {
            Text(Date.now.formatted(.dateTime.weekday(.abbreviated).day()))
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(theme.accentText)
            Text("\(dueCount)").font(.system(size: 34, weight: .bold)).foregroundStyle(overdue > 0 ? theme.red400 : theme.textPrimary)
            Text(dueCount == 1 ? "item due" : "items due").font(.system(size: 12)).foregroundStyle(theme.textMuted)
            Spacer(minLength: 0)
            if let next = d.focusTasks.first {
                Text(next.title).font(.system(size: 12, weight: .medium)).foregroundStyle(theme.text200).lineLimit(2)
            } else if !d.routines.isEmpty {
                Text("\(d.routines.filter(\.completedToday).count)/\(d.routines.count) routines done")
                    .font(.system(size: 12)).foregroundStyle(theme.text400)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetURL(URL(string: "obelo://open/today"))
    }
}

private struct ListView: View {
    @Environment(\.theme) private var theme
    let d: Dashboard
    let maxRows: Int
    var compactHeader = false

    var body: some View {
        let items = rows(d)
        VStack(alignment: .leading, spacing: 7) {
            Header(d: d, compact: compactHeader)
            if items.isEmpty {
                Spacer()
                Text("All clear for today 🎉").font(.system(size: 13)).foregroundStyle(theme.textMuted).frame(maxWidth: .infinity)
                Spacer()
            } else {
                ForEach(items.prefix(maxRows)) { ItemRow(row: $0) }
                if items.count > maxRows {
                    Text("+\(items.count - maxRows) more").font(.system(size: 11)).foregroundStyle(theme.textMuted)
                }
                Spacer(minLength: 0)
            }
        }
        .widgetURL(URL(string: "obelo://open/today"))
    }
}

private struct LargeView: View {
    @Environment(\.theme) private var theme
    let d: Dashboard

    var body: some View {
        let items = rows(d)
        VStack(alignment: .leading, spacing: 8) {
            Header(d: d)
            section("FOCUS & DUE")
            if items.isEmpty {
                Text("All clear for today 🎉").font(.system(size: 13)).foregroundStyle(theme.textMuted)
            } else {
                ForEach(items.prefix(6)) { ItemRow(row: $0) }
                if items.count > 6 { Text("+\(items.count - 6) more").font(.system(size: 11)).foregroundStyle(theme.textMuted) }
            }
            let upcoming = d.events.filter { $0.allDay || $0.endAt > .now }.prefix(2)
            if !upcoming.isEmpty {
                section("EVENTS").padding(.top, 4)
                ForEach(Array(upcoming)) { ev in
                    HStack(spacing: 8) {
                        Circle().fill(Color(hex: ev.color)).frame(width: 7, height: 7)
                        Text(ev.title).font(.system(size: 13)).foregroundStyle(theme.text200).lineLimit(1)
                        Spacer()
                        Text(ev.allDay ? "All day" : Fmt.clock(ev.startAt, hour12: true, tz: .current))
                            .font(.system(size: 11)).foregroundStyle(theme.textMuted)
                    }
                }
            }
            Spacer(minLength: 0)
            if !d.routines.isEmpty {
                let done = d.routines.filter(\.completedToday).count
                VStack(alignment: .leading, spacing: 4) {
                    Text("Routines \(done)/\(d.routines.count)").font(.system(size: 11, weight: .medium)).foregroundStyle(theme.text400)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(theme.h2)
                            Capsule().fill(theme.green500).frame(width: geo.size.width * CGFloat(done) / CGFloat(max(1, d.routines.count)))
                        }
                    }
                    .frame(height: 5)
                }
            }
        }
        .widgetURL(URL(string: "obelo://open/today"))
    }

    private func section(_ title: String) -> some View {
        Text(title).font(.system(size: 10, weight: .semibold)).tracking(0.8).foregroundStyle(theme.textMuted)
    }
}

private struct LockView: View {
    let d: Dashboard
    var body: some View {
        let overdue = d.due.filter(\.overdue).count
        VStack(alignment: .leading, spacing: 1) {
            Text("Obelo").font(.system(size: 12, weight: .semibold))
            Text("\(d.due.count) due\(overdue > 0 ? " · \(overdue) overdue" : "")").font(.system(size: 13))
            if let next = d.focusTasks.first { Text(next.title).font(.system(size: 12)).lineLimit(1).opacity(0.8) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetURL(URL(string: "obelo://open/today"))
    }
}

// ── Gallery placeholder ──────────────────────────────────────────────────────

extension Dashboard {
    static var sample: Dashboard {
        let now = Date.now
        func task(_ id: Int, _ title: String, _ priority: String, due: String? = nil, time: String? = nil, state: String? = nil) -> TaskItem {
            TaskItem(id: id, title: title, notes: "", status: "today", priority: priority, dueDate: due, dueTime: time, tags: [],
                     recurring: false, recurRule: nil, parentId: nil, createdAt: now, updatedAt: now, completedAt: nil, dueState: state)
        }
        return Dashboard(
            widgets: [], slippingCount: 0,
            focusTasks: [task(1, "Finish quarterly report", "high", time: "17:00"), task(2, "Review pull requests", "medium")],
            events: [], due: [Dashboard.DueEntry(type: "task", overdue: true, task: task(3, "Book dentist appointment", "low", due: Fmt.ymd(now), state: "overdue"), reminder: nil)],
            routines: [], resurfaced: nil, review: [], stale: []
        )
    }
}
