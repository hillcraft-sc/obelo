import SwiftUI

/// What the menu bar can ask of the Analytics screen (View ▸ Show 30 Days, 90 Days, All Time)
struct AnalyticsActions {
    let setRange: (AnalyticsRange) -> Void
}

extension FocusedValues {
    @Entry var analyticsActions: AnalyticsActions?
}

/// Analytics: what stands out, the summary tiles and the charts, in two columns when the window is wide
/// Read only: nothing here changes data.
struct AnalyticsScreen: View {
    @Environment(AppState.self) private var app
    @Environment(KitToastCenter.self) private var toast
    @Environment(MacRouter.self) private var router
    @Environment(\.theme) private var theme
    @State private var store = Self.makeStore()
    @State private var width: CGFloat = 1000
    @State private var position = ScrollPosition()

    private static func makeStore() -> AnalyticsStore {
        #if DEBUG
        MacDebug.analyticsStore()
        #else
        AnalyticsStore()
        #endif
    }

    /// Two columns from this width on
    private var wide: Bool { width >= 860 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if !store.findings.isEmpty { findings }
                heading
                if store.showsSmallSampleNotice { KitBanner(kind: .neutral, text: store.smallSampleText) }
                if let d = store.data {
                    AnalyticsSummary(data: d)
                    AnalyticsCharts(store: store, data: d, wide: wide)
                } else if !store.loaded && store.error == nil {
                    KitEmptyState(message: "Loading…")
                }
            }
            .padding(24)
            .frame(maxWidth: 1100, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollPosition($position)
        .scrollEdgeEffectHidden(true, for: .top)
        .background(theme.page)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .task(id: app.dataVersion) {
            await store.load()
            #if DEBUG
            // Testing: `-analyticsScroll 900` scrolls that far down
            let y = UserDefaults.standard.double(forKey: "analyticsScroll")
            if y > 0 { try? await Task.sleep(for: .seconds(0.5)); position.scrollTo(y: y) }
            #endif
        }
        .onChange(of: store.error) { _, message in
            guard let message else { return }
            toast.show(message, isError: true)
            store.error = nil
        }
        .focusedSceneValue(\.analyticsActions, AnalyticsActions(setRange: { choose($0) }))
    }

    private func choose(_ r: AnalyticsRange) {
        Task { await store.setRange(r) }
    }

    private var heading: some View {
        KitPageHeading(title: "Analytics", description: "When you finish tasks, reminders and routines, compared with when they were due.") {
            KitPillSelector(options: AnalyticsRange.allCases.map { ($0, $0.label) },
                            selection: Binding(get: { store.range }, set: { choose($0) }),
                            label: "Range")
        }
    }

    // ── What stands out ─────────────────────────────────────────────────────

    private var findings: some View {
        KitCard {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("What stands out").font(.system(size: 14, weight: .semibold)).foregroundStyle(theme.text100)
                        .accessibilityAddTraits(.isHeader)
                    Text("A few findings from your own data." + (store.findingsByAI ? " Worded by AI." : ""))
                        .font(.system(size: 12)).foregroundStyle(theme.textMuted)
                }
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(store.findings, id: \.self) { f in finding(f) }
                }
            }
            .padding(20)
        }
    }

    private func finding(_ f: Analytics.Finding) -> some View {
        let dot: Color = f.tone == "good" ? theme.green400 : f.tone == "warn" ? theme.amber400 : theme.textMuted
        let destination = Self.destination(f)
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Circle().fill(dot).frame(width: 7, height: 7).alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }.accessibilityHidden(true)
            if let destination {
                KitLinkButton(title: f.text, size: 14, tone: .muted) { router.open(destination) }
                    .multilineTextAlignment(.leading)
                    .help("Open")
            } else {
                Text(f.text).font(.system(size: 14)).foregroundStyle(theme.text400)
            }
            Spacer(minLength: 0)
        }
        .contextMenu {
            if let destination { Button("Open") { router.open(destination) } }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel((f.tone == "warn" ? "Needs attention: " : f.tone == "good" ? "Going well: " : "") + f.text)
    }

    /// The Mac screen for a finding's link
    static func destination(_ f: Analytics.Finding) -> MacRouter.Destination? {
        guard let t = f.target else { return nil }
        guard let id = t.id else { return .module(t.module) }
        switch t.module {
        case "tasks": return .tasks(view: nil, task: id)
        case "reminders": return .reminder(id)
        case "routines": return .routine(id)
        default: return .note(id)
        }
    }
}

/// The two big rates and the five small tiles
private struct AnalyticsSummary: View {
    @Environment(\.theme) private var theme
    let data: Analytics

    var body: some View {
        let s = data.summary
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                KitStatTile(title: "True on-time rate", value: s.trueOnTimeRate.map { "\($0)%" } ?? "—",
                            note: s.trueOnTimeRate == nil ? "No items with due dates yet." : "within 30 min of due time · \(AnalyticsStore.plural(s.withDueCount, "item")) with due dates",
                            valueColor: RateBand(s.trueOnTimeRate).text(theme), hero: true)
                KitStatTile(title: "Same-day rate", value: s.sameDayRate.map { "\($0)%" } ?? "—",
                            note: s.sameDayRate == nil ? "No items with due dates yet." : "completed on the due day",
                            valueColor: s.sameDayRate == nil ? theme.textMuted : RateBand(s.sameDayRate).text(theme).opacity(0.85), hero: true)
            }
            HStack(alignment: .top, spacing: 10) {
                KitStatTile(title: "Completed", value: "\(s.total)", note: data.rangeLabel)
                KitStatTile(title: "Avg days late", value: s.avgDaysLate.map { String(format: "%g", $0) } ?? "—",
                            note: s.avgDaysLate == nil ? "none late" : "days (when late)",
                            valueColor: s.avgDaysLate == nil ? theme.textMuted : theme.amber500)
                KitStatTile(title: "Best day", value: s.topDay ?? "—", note: s.topDay == nil ? "no data yet" : "\(s.topDayCount) completions", compact: true)
                KitStatTile(title: "Current streak", value: "\(data.streak.current)",
                            note: data.streak.current > 0 ? "day\(data.streak.current == 1 ? "" : "s") in a row" : "no recent completions",
                            valueColor: data.streak.current > 0 ? theme.accentText : theme.textMuted)
                KitStatTile(title: "Best streak", value: data.streak.best > 0 ? "\(data.streak.best)" : "—",
                            note: data.streak.best > 0 ? "day\(data.streak.best == 1 ? "" : "s") · all time" : "all time",
                            valueColor: data.streak.best > 0 ? theme.accentText : theme.textMuted)
            }
        }
    }
}
