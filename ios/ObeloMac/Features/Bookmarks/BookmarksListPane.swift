import SwiftUI

/// The left pane (web: bookmarks/index.ejs): heading, "New bookmark", the filter box, the tag filter, the bulk
/// bar, and the table
struct BookmarksListPane: View {
    @Environment(\.theme) private var theme
    @Bindable var model: BookmarksScreenModel
    @FocusState private var listFocused: Bool

    private var store: BookmarksStore { model.store }

    private static let title = KitTableColumn(id: "title", label: "Title")
    private static let site = KitTableColumn(id: "site", label: "Site", width: 150)
    private static let tags = KitTableColumn(id: "tags", label: "Tags", width: 150)
    private static let added = KitTableColumn(id: "added", label: "Added", width: 96)

    /// Fewer columns as the pane narrows
    private func columns(for width: CGFloat) -> [KitTableColumn] {
        if width >= 700 { return [Self.title, Self.site, Self.tags, Self.added] }
        if width >= 540 { return [Self.title, Self.site, Self.added] }
        return [Self.title, Self.added]
    }

    var body: some View {
        GeometryReader { geo in
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        KitPageHeading(title: "Bookmarks", description: "Saved links, always a click away.") {
                            Button("New bookmark") { model.newBookmark() }
                                .buttonStyle(KitButtonStyle(.primary))
                        }
                        KitSearchField(placeholder: "Filter bookmarks…", text: Binding(get: { store.search }, set: { store.search = $0 }), focusRequest: $model.focusFilter)
                        if !store.tagList.isEmpty { tagFilter }
                        table(columns(for: geo.size.width))
                        if !store.visible.isEmpty {
                            Text("\(store.visible.count) bookmark\(store.visible.count == 1 ? "" : "s")")
                                .font(.system(size: 12)).foregroundStyle(theme.textMuted)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity)
                }
                .scrollEdgeEffectHidden(true, for: .top)
                .onChange(of: store.selection.single) { _, id in
                    if let id { withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(id) } }
                }
            }
        }
    }

    private var tagFilter: some View {
        KitFlowLayout(spacing: 6) {
            Button { store.activeTag = nil } label: {
                Text("All").font(.system(size: 12, weight: .medium))
                    .foregroundStyle(store.activeTag == nil ? theme.onAccent : theme.textMuted)
                    .padding(.horizontal, 12).padding(.vertical, 4)
                    .background(store.activeTag == nil ? theme.accent : theme.elevated, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(store.activeTag == nil ? .isSelected : [])
            ForEach(store.tagList, id: \.self) { tag in
                KitTagFilterPill(tag: tag, active: store.activeTag == tag) { store.toggleTag(tag) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func table(_ columns: [KitTableColumn]) -> some View {
        KitCard {
            if store.selection.count > 1 {
                KitBulkDeleteBar(count: store.selection.count, onDelete: { model.requestDelete() },
                                 onCancel: { store.clearSelection(); model.syncPane() })
            }
            if !store.loaded {
                KitEmptyState(message: "Loading…")
            } else if store.visible.isEmpty {
                if store.isFiltered {
                    KitEmptyState(message: "No bookmarks match this filter.", actionLabel: "Clear filter") { store.clearFilter() }
                } else {
                    KitEmptyState(message: "No bookmarks yet.", actionLabel: "New bookmark") { model.newBookmark() }
                }
            } else {
                KitTableHeader(columns: columns, sortedBy: store.sortKey.rawValue, ascending: store.ascending) { id in
                    if let key = BookmarkSortKey(rawValue: id) { store.sort(by: key) }
                }
                LazyVStack(spacing: 0) {
                    ForEach(store.visible) { b in
                        BookmarkRow(model: model, bookmark: b, columns: columns, listFocused: $listFocused)
                            .id(b.id)
                        KitDivider()
                    }
                }
                .focusable()
                .focusEffectDisabled()
                .focused($listFocused)
                .onKeyPress(.downArrow) { keyAct { store.arrow(1); model.syncPane() } }
                .onKeyPress(.upArrow) { keyAct { store.arrow(-1); model.syncPane() } }
                .onKeyPress(.escape) { keyAct { store.clearSelection(); model.syncPane() } }
                .onKeyPress(.return) { keyAct { model.openSelection() } }
                .onKeyPress(.delete) { keyAct { model.requestDelete() } }
                .onKeyPress(.deleteForward) { keyAct { model.requestDelete() } }
                .onKeyPress(characters: CharacterSet(charactersIn: "a"), phases: .down) { press in
                    guard press.modifiers.contains(.command) else { return .ignored }
                    return keyAct { store.selectAll(); model.syncPane() }
                }
            }
        }
    }

    /// Runs a list key unless a text field has the cursor (then the key belongs to the field)
    private func keyAct(_ action: () -> Void) -> KeyPress.Result {
        guard !MacFocus.isEditingText else { return .ignored }
        action()
        return .handled
    }
}

/// One row of the table
private struct BookmarkRow: View {
    @Environment(\.theme) private var theme
    @Bindable var model: BookmarksScreenModel
    let bookmark: Bookmark
    let columns: [KitTableColumn]
    var listFocused: FocusState<Bool>.Binding

    private var store: BookmarksStore { model.store }

    var body: some View {
        KitRow(isSelected: store.selection.contains(bookmark.id), onClick: { command, shift in
            listFocused.wrappedValue = true
            model.click(bookmark.id, command: command, shift: shift)
        }) { _ in
            HStack(alignment: .top, spacing: 12) {
                ForEach(columns) { column in cell(column).kitTableCell(column) }
            }
        }
        .simultaneousGesture(TapGesture(count: 2).onEnded { model.open(bookmark) })
        .contextMenu {
            Button("Open in Browser") { model.open(bookmark) }.disabled(!bookmark.isWebLink)
            Button("Copy Link") { model.copyLink(bookmark) }
            Divider()
            Button("Edit…") { model.ensureSelected(bookmark.id); model.edit() }
            Button("Share…") { model.openShare(bookmark.id) }
            Divider()
            Button("Delete…", role: .destructive) { model.requestDelete(bookmark.id) }
        }
        .accessibilityLabel("\(bookmark.displayTitle), \(bookmark.site)")
    }

    /// Each tag filters the table by it
    private func tagLinks(_ tags: [String]) -> some View {
        KitFlowLayout(spacing: 4) {
            ForEach(tags, id: \.self) { tag in
                Button { store.toggleTag(tag) } label: { KitTagLabel(tag: tag) }
                    .buttonStyle(.plain).help("Show only #\(tag)")
            }
        }
    }

    @ViewBuilder private func cell(_ column: KitTableColumn) -> some View {
        switch column.id {
        case "title":
            HStack(alignment: .top, spacing: 8) {
                KitSiteIcon(host: bookmark.site).padding(.top, 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(bookmark.displayTitle).font(.system(size: 14, weight: .medium)).foregroundStyle(theme.text100).lineLimit(1)
                    Text(bookmark.url).font(.system(size: 12)).foregroundStyle(theme.textMuted).lineLimit(1)
                    if let d = bookmark.description, !d.isEmpty {
                        Text(d).font(.system(size: 12)).foregroundStyle(theme.text400).lineLimit(2).padding(.top, 2)
                    }
                    // With no Tags column (a narrow pane) the tags go under the title, as on the web
                    if !columns.contains(where: { $0.id == "tags" }), !bookmark.tags.isEmpty { tagLinks(bookmark.tags).padding(.top, 4) }
                }
            }
        case "site":
            Text(bookmark.site).font(.system(size: 13)).foregroundStyle(theme.accentText).lineLimit(1)
        case "tags":
            tagLinks(bookmark.tags)
        default:
            Text(bookmark.createdAt.formatted(.dateTime.month(.abbreviated).day().year()))
                .font(.system(size: 13)).foregroundStyle(theme.textMuted).lineLimit(1)
        }
    }
}
