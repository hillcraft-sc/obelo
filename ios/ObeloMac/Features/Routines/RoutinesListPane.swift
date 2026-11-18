import SwiftUI

/// The left pane (web: routines/index.ejs): heading, tabs, tag filter, bulk bar, rows by time of day, count
struct RoutinesListPane: View {
    @Environment(\.theme) private var theme
    @Bindable var model: RoutinesScreenModel
    @FocusState private var listFocused: Bool

    private var store: RoutinesStore { model.store }

    private var tabs: [KitTab] {
        [KitTab(id: "today", label: "Today"), KitTab(id: "all", label: "All"), KitTab(id: "archived", label: "Archived")]
    }

    var body: some View {
        GeometryReader { geo in
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        KitPageHeading(title: "Routines", description: "Habits that repeat on a schedule.") {
                            Button("New routine") { Task { await model.newRoutine() } }
                                .buttonStyle(KitButtonStyle(.primary))
                        }
                        KitTabs(tabs: tabs, selection: Binding(get: { store.view }, set: { v in Task { await model.show(view: v) } }))
                        if !store.tagList.isEmpty { tagFilter }
                        list(showFrequency: geo.size.width >= 480)
                        if !store.routines.isEmpty {
                            Text("\(store.routines.count) routine\(store.routines.count == 1 ? "" : "s")")
                                .font(.system(size: 12)).foregroundStyle(theme.textMuted)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        if !store.completedStreaks.isEmpty { completedStreaks }
                    }
                    .padding(24)
                    .frame(maxWidth: KitWidth.list)
                    .frame(maxWidth: .infinity)
                }
                .scrollEdgeEffectHidden(true, for: .top)
                .onChange(of: model.rows.single) { _, id in
                    if let id { withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(id) } }
                }
            }
        }
    }

    private var tagFilter: some View {
        KitFlowLayout(spacing: 6) {
            ForEach(store.tagList, id: \.self) { tag in
                KitTagFilterPill(tag: tag, active: store.tag == tag) { Task { await model.toggleTag(tag) } }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func list(showFrequency: Bool) -> some View {
        KitCard {
            if model.rows.count > 1 {
                KitBulkBar(count: model.rows.count,
                           actions: store.bulkChoices.map { (value: $0.0, label: $0.1) },
                           action: $model.bulkAction,
                           onApply: { Task { await model.applyBulk() } },
                           onCancel: { model.clearSelection() })
            }
            if store.routines.isEmpty || (store.view == "today" && store.dueGroups.isEmpty && store.notDueToday.isEmpty) {
                emptyState
            } else {
                LazyVStack(spacing: 0, pinnedViews: []) {
                    if store.view == "today" {
                        if store.dueGroups.isEmpty {
                            Text("Nothing due today.").font(.system(size: 14)).foregroundStyle(theme.textMuted)
                                .frame(maxWidth: .infinity).padding(.vertical, 24)
                            KitDivider()
                        }
                        ForEach(store.dueGroups, id: \.timeOfDay) { group in
                            KitGroupHeaderRow(text: RoutinesStore.timeLabels[group.timeOfDay] ?? group.timeOfDay)
                            ForEach(group.routines) { routine in
                                MacRoutineRow(model: model, routine: routine, showFrequency: showFrequency, listFocused: $listFocused).id(routine.id)
                                KitDivider()
                            }
                        }
                        if !store.notDueToday.isEmpty {
                            KitGroupHeaderRow(text: "Not due today")
                            ForEach(store.notDueToday) { routine in
                                MacRoutineRow(model: model, routine: routine, showFrequency: showFrequency, listFocused: $listFocused)
                                    .opacity(0.6).id(routine.id)
                                KitDivider()
                            }
                        }
                    } else {
                        ForEach(store.routines) { routine in
                            MacRoutineRow(model: model, routine: routine, showFrequency: showFrequency, listFocused: $listFocused).id(routine.id)
                            KitDivider()
                        }
                    }
                }
                .focusable()
                .focusEffectDisabled()
                .focused($listFocused)
                .onKeyPress(.downArrow) { keyAct { model.arrow(1) } }
                .onKeyPress(.upArrow) { keyAct { model.arrow(-1) } }
                .onKeyPress(.escape) { keyAct { model.clearSelection() } }
                .onKeyPress(.space) { keyAct { Task { await model.completeSelection() } } }
                .onKeyPress(.delete) { keyAct { model.requestDeleteSelection() } }
                .onKeyPress(.deleteForward) { keyAct { model.requestDeleteSelection() } }
            }
        }
    }

    /// Runs a list key unless a text field has the cursor (then the key belongs to the field)
    private func keyAct(_ action: () -> Void) -> KeyPress.Result {
        guard !MacFocus.isEditingText else { return .ignored }
        action()
        return .handled
    }

    @ViewBuilder private var emptyState: some View {
        if !store.loaded {
            KitEmptyState(message: "Loading…")
        } else if store.isFiltered {
            KitEmptyState(message: model.emptyMessage, actionLabel: "Clear filter") { Task { await model.clearFilter() } }
        } else if store.view == "archived" {
            KitEmptyState(message: model.emptyMessage)
        } else {
            KitEmptyState(message: model.emptyMessage, actionLabel: "New routine") { Task { await model.newRoutine() } }
        }
    }

    /// Archived tab: routines that reached their goal (web: "Completed Streaks")
    private var completedStreaks: some View {
        VStack(alignment: .leading, spacing: 10) {
            KitGroupLabel(text: "Completed Streaks")
            ForEach(store.completedStreaks) { r in
                let goal = r.durationDays ?? r.completionCount
                let pct = goal > 0 ? Int((Double(r.completionCount) / Double(goal) * 100).rounded()) : 100
                KitCard {
                    HStack(spacing: 14) {
                        Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(theme.green400).accessibilityHidden(true)
                            .frame(width: 32, height: 32)
                            .background(theme.green500.opacity(0.12), in: Circle())
                            .overlay(Circle().strokeBorder(theme.green700))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.title).font(.system(size: 14, weight: .medium)).foregroundStyle(theme.text200).lineLimit(1)
                            Text("\(r.completionCount)/\(goal) days — \(pct)%" + (r.streakBest > 0 ? " · Best streak: \(r.streakBest) days" : ""))
                                .font(.system(size: 12)).foregroundStyle(theme.textMuted)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .contentShape(Rectangle())
                    .onTapGesture { model.click(r.id, command: false, shift: false) }
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isButton)
                }
            }
        }
    }
}
