import SwiftUI

/// The right pane (web: lists/show.ejs): the title, the items, "Send as text message", sharing; or the
/// "New list" form
struct ListDetailPane: View {
    @Environment(\.theme) private var theme
    @Bindable var model: ListsScreenModel

    var body: some View {
        Group {
            if model.newName != nil {
                NewListForm(model: model)
            } else if let list = model.store.open, list.id == model.store.selectedID {
                ListEditor(model: model, list: list)
            } else {
                KitEmptyState(message: "Select a list.")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.page)
    }
}

private struct NewListForm: View {
    @Environment(\.theme) private var theme
    @Bindable var model: ListsScreenModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("New list").font(.system(size: 24, weight: .bold)).foregroundStyle(theme.textPrimary)
                KitTextField(placeholder: "New list name…", text: Binding(get: { model.newName ?? "" }, set: { model.newName = $0 }),
                             onSubmit: { Task { await model.createNew() } }, focusRequest: $model.focusNewName,
                             onCancel: { model.cancelNew() })
                HStack(spacing: 8) {
                    Button("Create") { Task { await model.createNew() } }
                        .buttonStyle(KitButtonStyle(.primary))
                        .disabled((model.newName ?? "").trimmingCharacters(in: .whitespaces).isEmpty)
                    Button("Cancel") { model.cancelNew() }.buttonStyle(KitButtonStyle(.secondary))
                }
            }
            .padding(24)
            .frame(maxWidth: KitWidth.form, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }
}

private struct ListEditor: View {
    @Environment(\.theme) private var theme
    @Bindable var model: ListsScreenModel
    let list: ListDetail
    @FocusState private var itemsFocused: Bool
    @State private var targeted: Int?

    private var store: ListsStore { model.store }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                addItem
                items
                KitCard {
                    HStack {
                        Button { model.sendAsText() } label: {
                            Label("Send as text message", systemImage: "message")
                        }
                        .buttonStyle(KitButtonStyle(.secondary))
                        Spacer()
                    }
                    .padding(12)
                }
                if list.isOwner { sharing }
            }
            .padding(24)
            .frame(maxWidth: KitWidth.form + 120, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollEdgeEffectHidden(true, for: .top)
        .onAppear { if model.focusAddItem { model.focusAddItem = false } }
    }

    // ── Title ───────────────────────────────────────────────────────────────

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                if list.isOwner {
                    KitTitleField(placeholder: "List name", text: $model.titleDraft,
                                  onSubmit: { Task { await model.commitTitle() } },
                                  onCancel: { model.revertTitle() }, focusRequest: $model.focusTitle)
                        .help("Click the name to rename the list. Return saves, Escape cancels.")
                } else {
                    Text(list.title).font(.system(size: 24, weight: .bold)).foregroundStyle(theme.textPrimary)
                }
                if !list.isOwner {
                    Text("Shared by \(list.owner ?? "someone")").font(.system(size: 12)).foregroundStyle(theme.textMuted)
                } else if !list.sharedWith.isEmpty {
                    Text("Shared with \(list.sharedWith.map(\.displayName).joined(separator: ", "))")
                        .font(.system(size: 12)).foregroundStyle(theme.textMuted)
                }
            }
            Spacer(minLength: 8)
            if list.isOwner {
                Button("Delete list") { model.requestDeleteOpenList() }
                    .buttonStyle(KitButtonStyle(.ghost, small: true))
            }
        }
    }

    // ── Items ───────────────────────────────────────────────────────────────

    private var addItem: some View {
        HStack(spacing: 8) {
            KitTextField(placeholder: "Add an item…", text: $model.itemText,
                         onSubmit: { Task { await model.addItem() } }, focusRequest: $model.focusAddItem)
            Button("Add") { Task { await model.addItem() } }.buttonStyle(KitButtonStyle(.primary))
        }
    }

    private var items: some View {
        KitCard {
            let active = store.activeItems, done = store.doneItems
            if active.isEmpty {
                Text("Nothing to do — add an item above").font(.system(size: 14)).foregroundStyle(theme.textMuted)
                    .frame(maxWidth: .infinity).padding(.vertical, 28)
                if !done.isEmpty { KitDivider() }
            }
            VStack(spacing: 0) {
                ForEach(active) { item in
                    ListItemRow(model: model, item: item, targeted: $targeted)
                    if item.id != active.last?.id || !done.isEmpty { KitDivider() }
                }
                ForEach(done) { item in
                    ListItemRow(model: model, item: item, targeted: $targeted)
                    if item.id != done.last?.id { KitDivider() }
                }
            }
            .focusable()
            .focusEffectDisabled()
            .focused($itemsFocused)
            .onKeyPress(.downArrow) { keyAct { model.arrow(1) } }
            .onKeyPress(.upArrow) { keyAct { model.arrow(-1) } }
            .onKeyPress(.escape) { keyAct { model.selectedItem = nil } }
            .onKeyPress(.space) { keyAct { if let id = model.selectedItem { Task { await model.toggle(id) } } } }
            .onKeyPress(.delete) { keyAct { if let id = model.selectedItem { Task { await model.deleteItem(id) } } } }
            .onKeyPress(.deleteForward) { keyAct { if let id = model.selectedItem { Task { await model.deleteItem(id) } } } }
            .onKeyPress(phases: .down) { press in
                guard press.modifiers.contains(.option), !MacFocus.isEditingText, let id = model.selectedItem else { return .ignored }
                switch press.key {
                case .upArrow: model.nudge(id, by: -1); return .handled
                case .downArrow: model.nudge(id, by: 1); return .handled
                default: return .ignored
                }
            }
        }
    }

    private func keyAct(_ action: () -> Void) -> KeyPress.Result {
        guard !MacFocus.isEditingText else { return .ignored }
        action()
        return .handled
    }

    // ── Sharing ─────────────────────────────────────────────────────────────

    private var sharing: some View {
        KitCard {
            KitCardHeader(title: "Share this list")
            VStack(alignment: .leading, spacing: 12) {
                ForEach(list.sharedWith) { person in
                    HStack(spacing: 10) {
                        KitAvatar(name: person.displayName)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(person.displayName).font(.system(size: 14)).foregroundStyle(theme.text200).lineLimit(1)
                            Text("@\(person.username)").font(.system(size: 12)).foregroundStyle(theme.textMuted)
                        }
                        Spacer(minLength: 8)
                        KitIconButton(systemImage: "xmark", label: "Remove access", destructive: true) {
                            Task { await model.store.unshare(person.id) }
                        }
                    }
                }
                HStack(spacing: 8) {
                    KitTextField(placeholder: "Username to share with…", text: $model.shareName, onSubmit: { Task { await model.share() } })
                    Button("Share") { Task { await model.share() } }
                        .buttonStyle(KitButtonStyle(.primary))
                        .disabled(model.shareName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                let suggestions = store.suggestions(for: model.shareName)
                if !suggestions.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        KitGroupLabel(text: "People")
                        ForEach(suggestions) { u in
                            KitLinkButton(title: "\(u.displayName) (@\(u.username))", size: 13, tone: .muted) { model.shareName = u.username }
                        }
                    }
                }
                Text("Shared users can add, edit, and check off items.").font(.system(size: 12)).foregroundStyle(theme.textMuted)
            }
            .padding(16)
            .task { await store.loadShareable() }
        }
    }
}

/// One item (web: partials/list-item.ejs): drag handle, checkbox, text, pencil and cross on hover
private struct ListItemRow: View {
    @Environment(\.theme) private var theme
    @Bindable var model: ListsScreenModel
    let item: ListEntry
    @Binding var targeted: Int?

    var body: some View {
        KitRow(isSelected: model.selectedItem == item.id, onClick: { _, _ in model.selectedItem = item.id }) { hovering in
            HStack(spacing: 10) {
                if item.checked { Color.clear.frame(width: 18, height: 24) } else { KitDragHandle(id: item.id) }
                KitCheckbox(title: item.checked ? "Mark \(item.text) not done" : "Mark \(item.text) done",
                            isOn: Binding(get: { item.checked }, set: { _ in Task { await model.toggle(item.id) } }), showsTitle: false)
                    .labelsHidden()
                if model.editingItem == item.id {
                    KitTextField(placeholder: "Item", text: $model.editText, onSubmit: { Task { await model.saveEdit() } },
                                 onCancel: { model.cancelEdit() })
                    KitLinkButton(title: "Save", size: 12) { Task { await model.saveEdit() } }
                    KitLinkButton(title: "Cancel", size: 12, tone: .muted) { model.cancelEdit() }
                } else {
                    Text(item.text).font(.system(size: 14))
                        .strikethrough(item.checked)
                        .foregroundStyle(item.checked ? theme.textMuted : theme.text100)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .onTapGesture(count: 2) { model.startEdit(item.id) }
                    KitIconButton(systemImage: "pencil", label: "Edit item") { model.startEdit(item.id) }.opacity(hovering ? 1 : 0)
                    KitIconButton(systemImage: "trash", label: "Delete item", destructive: true) { Task { await model.deleteItem(item.id) } }
                        .opacity(hovering ? 1 : 0)
                }
            }
        }
        .kitReorderTarget(isTargeted: Binding(get: { targeted == item.id }, set: { targeted = $0 ? item.id : nil })) { dragged in
            item.checked ? false : model.drop(dragged, onto: item.id)
        }
        .contextMenu {
            Button("Edit") { model.startEdit(item.id) }
            Button(item.checked ? "Mark Not Done" : "Mark Done") { Task { await model.toggle(item.id) } }
            Divider()
            Button("Delete", role: .destructive) { Task { await model.deleteItem(item.id) } }
        }
    }
}
