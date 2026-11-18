import SwiftUI

/// The left pane (web: reminders/index.ejs): heading, tabs, tag filter, bulk bar, rows, count
struct RemindersListPane: View {
    @Environment(\.theme) private var theme
    @Bindable var model: RemindersScreenModel
    @FocusState private var listFocused: Bool

    private var store: RemindersStore { model.store }

    private var tabs: [KitTab] {
        [KitTab(id: "upcoming", label: "Upcoming"),
         KitTab(id: "today", label: "Today", badge: store.counts.today),
         KitTab(id: "overdue", label: "Overdue", badge: store.counts.overdue, warn: true),
         KitTab(id: "completed", label: "Completed")]
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    KitPageHeading(title: "Reminders", description: "One-off nudges at a set date and time.") {
                        Button("New reminder") { Task { await model.newReminder() } }
                            .buttonStyle(KitButtonStyle(.primary))
                    }
                    KitTabs(tabs: tabs, selection: Binding(get: { store.view }, set: { v in Task { await model.show(view: v) } }))
                    if !store.tagList.isEmpty { tagFilter }
                    list
                    if !store.reminders.isEmpty {
                        Text("\(store.reminders.count) reminder\(store.reminders.count == 1 ? "" : "s")")
                            .font(.system(size: 12)).foregroundStyle(theme.textMuted)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
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

    private var tagFilter: some View {
        KitFlowLayout(spacing: 6) {
            ForEach(store.tagList, id: \.self) { tag in
                KitTagFilterPill(tag: tag, active: store.tag == tag) { Task { await model.toggleTag(tag) } }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var list: some View {
        KitCard {
            if model.rows.count > 1 {
                KitBulkBar(count: model.rows.count,
                           actions: store.bulkChoices.map { (value: $0.0, label: $0.1) },
                           action: $model.bulkAction,
                           onApply: { Task { await model.applyBulk() } },
                           onCancel: { model.clearSelection() })
                    .onChange(of: store.view) { model.bulkAction = store.bulkChoices.first?.0 ?? "delete" }
            }
            if store.reminders.isEmpty {
                emptyState
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(store.reminders) { reminder in
                        MacReminderRow(model: model, reminder: reminder, listFocused: $listFocused).id(reminder.id)
                        KitDivider()
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
        } else if store.view == "completed" {
            KitEmptyState(message: model.emptyMessage)
        } else {
            KitEmptyState(message: model.emptyMessage, actionLabel: "New reminder") { Task { await model.newReminder() } }
        }
    }
}
