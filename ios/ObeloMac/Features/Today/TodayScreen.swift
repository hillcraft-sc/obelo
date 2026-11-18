import SwiftUI

/// Today (web: dashboard/index.ejs): the date and time, then the cards the person has switched on, in
/// their order (Settings ▸ Dashboard), then Quick Capture. Two columns when the window is wide.
struct TodayScreen: View {
    @Environment(AppState.self) private var app
    @Environment(KitToastCenter.self) private var toast
    @Environment(MacRouter.self) private var router
    @Environment(\.theme) private var theme
    @State private var store = Self.makeStore()
    @State private var captureText = ""

    private static func makeStore() -> TodayStore {
        #if DEBUG
        MacDebug.todayStore()
        #else
        TodayStore()
        #endif
    }

    private var timeZone: TimeZone { TimeZone(identifier: app.me?.user.timezone ?? "") ?? .current }

    /// A card shows only when the web page would show it: due items, routines, a resurfaced note and
    /// review items are hidden when empty; My Focus and Today's Events always show their empty line
    private var visibleCards: [String] {
        store.cards.filter { key in
            switch key {
            case "due_items": !store.due.isEmpty
            case "routines": !store.routines.isEmpty
            case "resurfaced": store.resurfaced != nil
            case "review": store.needsReviewCount > 0
            default: true
            }
        }
    }

    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width >= 960
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    if store.loaded { cards(wide: wide) }
                    quickCapture
                }
                .padding(24)
                .frame(maxWidth: wide ? 1024 : KitWidth.list, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
        .scrollEdgeEffectHidden(true, for: .top)
        .background(theme.page)
        .task { await store.load() }
        .onChange(of: app.dataVersion) { Task { await store.load() } }
        .onChange(of: store.error) { _, message in
            guard let message else { return }
            toast.show(message, isError: true)
            store.error = nil
        }
        .onChange(of: store.notice) { _, message in
            guard let message else { return }
            toast.show(message)
            store.notice = nil
        }
    }

    // ── Header ──────────────────────────────────────────────────────────────

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            // Redrawn every 30 seconds, like the web page's clock
            TimelineView(.periodic(from: .now, by: 30)) { context in
                VStack(alignment: .leading, spacing: 2) {
                    Text(Self.dateText(context.date, in: timeZone))
                        .font(.system(size: 24, weight: .bold)).foregroundStyle(theme.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    Text(Fmt.clock(context.date, hour12: app.hour12, tz: timeZone))
                        .font(.system(size: 14)).foregroundStyle(theme.textMuted)
                }
            }
            Spacer(minLength: 12)
            if store.slippingCount > 0 {
                Button { router.open(.tasks(view: "slipping", task: nil)) } label: {
                    KitBadge(text: "\(store.slippingCount) task\(store.slippingCount == 1 ? "" : "s") slipping", tone: .warn, outlined: true)
                }
                .buttonStyle(.plain)
                .help("Show slipping tasks")
            }
        }
    }

    private static func dateText(_ date: Date, in tz: TimeZone) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.timeZone = tz
        f.dateFormat = "EEEE, MMMM d"
        return f.string(from: date)
    }

    // ── Cards ───────────────────────────────────────────────────────────────

    @ViewBuilder private func cards(wide: Bool) -> some View {
        let keys = visibleCards
        if wide {
            let columns = split(keys)
            HStack(alignment: .top, spacing: 20) {
                VStack(spacing: 20) { ForEach(columns.0, id: \.self) { card($0) } }
                VStack(spacing: 20) { ForEach(columns.1, id: \.self) { card($0) } }
            }
        } else {
            VStack(spacing: 20) { ForEach(keys, id: \.self) { card($0) } }
        }
    }

    /// Each card goes under the shorter column, in the person's order. The height is guessed from the rows.
    private func split(_ keys: [String]) -> ([String], [String]) {
        var left: [String] = [], right: [String] = []
        var leftHeight = 0, rightHeight = 0
        for key in keys {
            let height = 2 + weight(key)
            if leftHeight <= rightHeight { left.append(key); leftHeight += height } else { right.append(key); rightHeight += height }
        }
        return (left, right)
    }

    private func weight(_ key: String) -> Int {
        switch key {
        case "focus": max(store.focusTasks.count, 1)
        case "calendar": max(store.events.count, 1)
        case "due_items": store.due.count
        case "routines": store.routines.count + store.routineGroups.count
        case "resurfaced": 3
        case "review": store.needsReviewCount
        default: 1
        }
    }

    @ViewBuilder private func card(_ key: String) -> some View {
        switch key {
        case "focus": FocusCard(store: store, timeZone: timeZone)
        case "calendar": EventsCard(store: store, timeZone: timeZone)
        case "due_items": DueCard(store: store)
        case "routines": RoutinesCard(store: store)
        case "resurfaced": ResurfacedCard(store: store)
        case "review": ReviewCard(store: store)
        default: EmptyView()
        }
    }

    // ── Quick Capture ───────────────────────────────────────────────────────

    private var quickCapture: some View {
        KitCard {
            KitCardHeader(title: "Quick Capture", uppercase: true)
            HStack(spacing: 8) {
                KitTextField(placeholder: "Capture a thought, task, or note…", text: $captureText,
                             onSubmit: { capture() }, onCancel: { captureText = "" })
                Button("Capture") { capture() }.buttonStyle(KitButtonStyle(.primary))
            }
            .padding(16)
        }
    }

    private func capture() {
        let text = captureText.trimmingCharacters(in: .whitespacesAndNewlines)
        router.captureText = text.isEmpty ? nil : text
        captureText = ""
        router.open(.module("capture"))
    }
}
