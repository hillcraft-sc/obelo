import SwiftUI

/// The grid and what is around it (web: calendar/index.ejs): the range as the heading, "New event", Week and
/// Month, Prev, Today and Next, the notice when no calendar is connected, the grid, the legend
struct CalendarGridPane: View {
    @Environment(AppState.self) private var app
    @Environment(\.theme) private var theme
    @Bindable var model: CalendarScreenModel
    @FocusState private var gridFocused: Bool

    private var store: CalendarStore { model.store }
    private var hour12: Bool { app.hour12 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                KitPageHeading(title: store.rangeLabel, description: "") {
                    Button { model.newEvent() } label: { Label("New event", systemImage: "plus") }
                        .buttonStyle(KitButtonStyle(.primary))
                }
                controls
                if store.showsNoCalendarsNotice {
                    KitBanner(kind: .warn, text: "No calendars connected. Events created here are stored locally only.")
                }
                if store.loaded {
                    KitCalendarGrid(isMonth: store.mode == .month, weeks: weeks, selectedEvent: store.selectedID,
                                    onEvent: { gridFocused = true; model.select($0) },
                                    onOpenEvent: { model.edit($0) },
                                    onDay: { model.newEvent(on: $0) },
                                    eventMenu: { id in eventMenu(id) },
                                    dayMenu: { day in
                                        Button("New Event on This Day") { model.newEvent(on: day) }
                                    })
                } else {
                    KitEmptyState(message: "Loading…")
                }
                if !store.sources.isEmpty { legend }
            }
            .padding(24)
            .frame(maxWidth: .infinity)
            .focusable()
            .focusEffectDisabled()
            .focused($gridFocused)
            .onKeyPress(.return) { keyAct { model.editSelected() } }
            .onKeyPress(.escape) { keyAct { model.close() } }
            .onKeyPress(.delete) { keyAct { model.requestDeleteSelected() } }
            .onKeyPress(.deleteForward) { keyAct { model.requestDeleteSelected() } }
        }
        .scrollEdgeEffectHidden(true, for: .top)
    }

    // ── Controls ────────────────────────────────────────────────────────────

    private var controls: some View {
        HStack(spacing: 12) {
            KitPillSelector(options: [(CalendarViewMode.week, "Week"), (CalendarViewMode.month, "Month")],
                            selection: Binding(get: { store.mode }, set: { model.setMode($0) }), label: "View")
            Spacer(minLength: 8)
            HStack(spacing: 4) {
                Button("‹ Prev") { model.previous() }.buttonStyle(KitButtonStyle(.secondary, small: true))
                Button("Today") { model.today() }.buttonStyle(KitButtonStyle(.secondary, small: true))
                Button("Next ›") { model.next() }.buttonStyle(KitButtonStyle(.secondary, small: true))
            }
        }
    }

    // ── Grid ────────────────────────────────────────────────────────────────

    private var weeks: [[KitCalendarDay]] {
        (0..<store.weekCount).map { w in
            store.days(inWeek: w).map { day in
                KitCalendarDay(id: day, number: CalendarMath.dayNumber(day), isToday: store.isToday(day), inMonth: store.isInMonth(day),
                               chips: store.events(on: day).map { e in
                                   KitCalendarChip(id: e.id, title: e.title, time: e.allDay ? nil : Fmt.time(e.startTime, hour12: hour12), color: e.color)
                               },
                               longName: Fmt.longDay(day))
            }
        }
    }

    @ViewBuilder private func eventMenu(_ id: Int) -> some View {
        if let e = store.events.first(where: { $0.id == id }) {
            Button("Open") { model.select(id) }
            if CalendarStore.isWebLink(e.url) { Button("Open Link in Browser") { model.open(e) } }
            if e.editable {
                Divider()
                Button("Edit…") { model.edit(id) }
                Button("Delete…", role: .destructive) { model.requestDelete(id) }
            }
        }
    }

    // ── Legend ──────────────────────────────────────────────────────────────

    private var legend: some View {
        KitFlowLayout(spacing: 16) {
            ForEach(store.sources) { src in
                HStack(spacing: 6) {
                    KitColorDot(hex: src.color)
                    Text(src.name).font(.system(size: 12)).foregroundStyle(theme.textMuted)
                    if let synced = src.lastSynced {
                        Text("· synced \(Fmt.clock(synced, hour12: hour12, tz: TimeZone(identifier: app.me?.user.timezone ?? "") ?? .current))")
                            .font(.system(size: 12)).foregroundStyle(theme.textMuted.opacity(0.7))
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Runs a grid key unless a text field has the cursor
    private func keyAct(_ action: () -> Void) -> KeyPress.Result {
        guard !MacFocus.isEditingText else { return .ignored }
        action()
        return .handled
    }
}
