import SwiftUI

/// The left pane (web: lists/index.ejs): heading, "New list", My Lists, Shared with me
struct ListsListPane: View {
    @Environment(\.theme) private var theme
    @Bindable var model: ListsScreenModel

    private var store: ListsStore { model.store }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                KitPageHeading(title: "Lists", description: "Quick, shareable checklists.") {
                    Button("New list") { Task { await model.newList() } }
                        .buttonStyle(KitButtonStyle(.primary))
                }
                if !store.loaded {
                    KitEmptyState(message: "Loading…")
                } else if store.isEmpty {
                    KitCard { KitEmptyState(message: "No lists yet.", actionLabel: "New list") { Task { await model.newList() } } }
                } else {
                    if !store.mine.isEmpty { section(store.showsMineHeading ? "My Lists" : nil, store.mine) }
                    if !store.shared.isEmpty { section("Shared with me", store.shared) }
                }
            }
            .padding(24)
            .frame(maxWidth: KitWidth.list)
            .frame(maxWidth: .infinity)
        }
        .scrollEdgeEffectHidden(true, for: .top)
    }

    @ViewBuilder private func section(_ heading: String?, _ lists: [ListSummary]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let heading { KitGroupLabel(text: heading) }
            KitCard {
                ForEach(lists) { list in
                    KitRow(isSelected: store.selectedID == list.id && model.newName == nil, onClick: { _, _ in
                        Task { await model.select(list.id) }
                    }) { _ in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 8) {
                                Text(list.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(theme.text100).lineLimit(1)
                                if !list.isOwner { KitBadge(text: "shared", tone: .info) }
                            }
                            Text((list.isOwner ? "" : "by \(list.owner ?? "someone") · ") + ListsStore.counts(list))
                                .font(.system(size: 12)).foregroundStyle(theme.textMuted).lineLimit(1)
                        }
                    }
                    .contextMenu {
                        if list.isOwner {
                            Button("Delete List…", role: .destructive) { model.pendingDeleteList = list.id }
                        }
                    }
                    if list.id != lists.last?.id { KitDivider() }
                }
            }
        }
    }
}
