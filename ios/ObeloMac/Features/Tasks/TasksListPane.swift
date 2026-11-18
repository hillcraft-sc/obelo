import SwiftUI

/// The left pane (web: tasks/index.ejs): heading, tabs, search, tag filter, quick add, bulk bar, rows, count
struct TasksListPane: View {
    @Environment(\.theme) private var theme
    @Bindable var model: TasksScreenModel
    @FocusState private var listFocused: Bool

    private var store: TasksStore { model.store }

    private var tabs: [KitTab] {
        [KitTab(id: "inbox", label: "Inbox", badge: store.counts.inbox),
         KitTab(id: "today", label: "Today", badge: store.counts.today),
         KitTab(id: "upcoming", label: "Upcoming"),
         KitTab(id: "all", label: "All"),
         KitTab(id: "completed", label: "Completed"),
         KitTab(id: "archived", label: "Archived"),
         KitTab(id: "slipping", label: "Slipping", badge: store.counts.slipping, warn: true)]
    }

    var body: some View {
        GeometryReader { geo in
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        KitPageHeading(title: "Tasks", description: "Everything you plan to do, from inbox to done.") {
                            Button("New task") { Task { await model.newTask() } }
                                .buttonStyle(KitButtonStyle(.primary))
                        }
                        KitTabs(tabs: tabs, selection: Binding(get: { store.view },
                                                               set: { v in Task { await model.show(view: v) } }))
                        KitSearchField(placeholder: "Search tasks...", text: Binding(get: { model.store.search }, set: { model.store.search = $0 }),
                                       focusRequest: $model.focusSearch)
                            .onChange(of: model.store.search) { model.searchChanged() }
                        if !store.tagList.isEmpty { tagFilter }
                        if store.canQuickAdd { quickAdd }
                        if store.view == "slipping", !store.tasks.isEmpty { slippingBanner }
                        list(showTags: geo.size.width >= 520)
                        if !store.tasks.isEmpty {
                            Text("\(store.tasks.count) task\(store.tasks.count == 1 ? "" : "s")")
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
    }

    private var tagFilter: some View {
        KitFlowLayout(spacing: 6) {
            ForEach(store.tagList, id: \.self) { tag in
                KitTagFilterPill(tag: tag, active: store.tag == tag) { Task { await model.toggleTag(tag) } }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var quickAdd: some View {
        HStack(spacing: 8) {
            KitTextField(placeholder: "Quick-add a task and press Enter...", text: $model.quickAddText,
                         onSubmit: { Task { await model.submitQuickAdd() } }, focusRequest: $model.focusQuickAdd)
            Button("Add") { Task { await model.submitQuickAdd() } }
                .buttonStyle(KitButtonStyle(.secondary))
        }
    }

    private var slippingBanner: some View {
        Text("These tasks haven't been updated in 7 days. Give them some attention or archive them.")
            .font(.system(size: 14)).foregroundStyle(theme.amber300)
            .padding(.horizontal, 16).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.amber950.opacity(0.5), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(theme.amber900))
    }

    @ViewBuilder private func list(showTags: Bool) -> some View {
        KitCard {
            if model.rows.count > 1 {
                KitBulkBar(count: model.rows.count,
                           actions: store.bulkChoices.map { (value: $0.0, label: $0.1) },
                           action: $model.bulkAction,
                           onApply: { Task { await model.applyBulk() } },
                           onCancel: { model.clearSelection() })
            }
            if store.tasks.isEmpty {
                emptyState
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(model.groups) { group in
                        if let title = group.title {
                            Text(title.uppercased())
                                .font(.system(size: 11, weight: .semibold)).tracking(0.6)
                                .foregroundStyle(theme.textMuted)
                                .padding(.horizontal, 16).padding(.vertical, 8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(theme.elevated.opacity(0.5))
                                .accessibilityAddTraits(.isHeader)
                        }
                        ForEach(group.tasks) { task in
                            MacTaskRow(model: model, task: task, showTags: showTags, listFocused: $listFocused)
                                .id(task.id)
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
        } else if ["completed", "archived", "slipping"].contains(store.view) {
            KitEmptyState(message: model.emptyMessage)
        } else {
            KitEmptyState(message: model.emptyMessage, actionLabel: "New task") { Task { await model.newTask() } }
        }
    }
}
