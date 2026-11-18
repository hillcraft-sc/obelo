import SwiftUI

/// The right pane: the form for a new bookmark, the form for the selected one (with Open, Share and Delete),
/// or a hint (web: the add form and the edit window in bookmarks/index.ejs)
struct BookmarkDetailPane: View {
    @Environment(\.theme) private var theme
    @Bindable var model: BookmarksScreenModel

    var body: some View {
        Group {
            switch model.mode {
            case .new, .edit:
                BookmarkEditForm(model: model)
            case .none:
                KitEmptyState(message: model.store.selection.count > 1 ? "\(model.store.selection.count) bookmarks selected." : "Select a bookmark.")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.page)
    }
}

private struct BookmarkEditForm: View {
    @Environment(\.theme) private var theme
    @Bindable var model: BookmarksScreenModel

    private var isNew: Bool { model.mode == .new }
    private var submit: () -> Void { { if model.canSave { Task { await model.save() } } } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    Text(isNew ? "New bookmark" : "Edit Bookmark")
                        .font(.system(size: 24, weight: .bold)).foregroundStyle(theme.textPrimary)
                    Spacer(minLength: 8)
                    if let b = model.editing { actions(b) }
                }
                KitFieldLabel(text: "URL") {
                    KitTextField(placeholder: "https://example.com", text: $model.draft.url,
                                 onSubmit: submit, focusRequest: $model.focusURL, onCancel: { model.cancel() })
                }
                KitFieldLabel(text: "Title") {
                    KitTextField(placeholder: "Title (optional)", text: $model.draft.title, onSubmit: submit, onCancel: { model.cancel() })
                }
                KitFieldLabel(text: "Note") {
                    KitTextField(placeholder: "Note (optional)", text: $model.draft.description, onSubmit: submit, onCancel: { model.cancel() })
                }
                KitFieldLabel(text: "Tags") {
                    KitTagPicker(tags: $model.draft.tags, suggestions: model.store.tagSuggestions)
                }
                HStack(spacing: 8) {
                    Button(isNew ? "Add" : "Save", action: submit)
                        .buttonStyle(KitButtonStyle(.primary))
                        .disabled(!model.canSave || (!isNew && !model.isDirty))
                    Button("Cancel") { model.cancel() }
                        .buttonStyle(KitButtonStyle(.secondary))
                        .disabled(!isNew && !model.isDirty)
                }
                .padding(.top, 4)
            }
            .padding(24)
            .frame(maxWidth: KitWidth.form, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollEdgeEffectHidden(true, for: .top)
    }

    /// Open, Share and Delete for the selected bookmark
    @ViewBuilder private func actions(_ b: Bookmark) -> some View {
        HStack(spacing: 4) {
            KitIconButton(systemImage: "arrow.up.right.square", label: "Open in browser") { model.open(b) }
                .disabled(!b.isWebLink)
            KitIconButton(systemImage: "square.and.arrow.up", label: "Share") { model.openShare(b.id) }
                .popover(isPresented: $model.showShare, arrowEdge: .bottom) { BookmarkSharePopover(model: model, bookmark: b) }
            KitIconButton(systemImage: "trash", label: "Delete bookmark", destructive: true) { model.requestDelete(b.id) }
        }
    }
}

/// The Share box (web: the "Share Bookmark" window): send to an Obelo user, share by text message, copy the link
private struct BookmarkSharePopover: View {
    @Environment(\.theme) private var theme
    @Bindable var model: BookmarksScreenModel
    let bookmark: Bookmark
    @State private var copied = false
    @State private var focusName = true

    private var suggestions: [ListDetail.SharedUser] { Array(model.store.suggestions(for: model.shareName).prefix(5)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Share Bookmark").font(.system(size: 14, weight: .semibold)).foregroundStyle(theme.text200)
                Text(bookmark.displayTitle).font(.system(size: 12)).foregroundStyle(theme.textMuted).lineLimit(1)
            }
            VStack(alignment: .leading, spacing: 8) {
                KitGroupLabel(text: "Send to Obelo user")
                HStack(spacing: 8) {
                    KitTextField(placeholder: "username", text: $model.shareName,
                                 onSubmit: { Task { await model.sendToUser() } }, focusRequest: $focusName)
                    Button("Send") { Task { await model.sendToUser() } }
                        .buttonStyle(KitButtonStyle(.primary))
                        .disabled(model.shareName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if !suggestions.isEmpty {
                    KitFlowLayout(spacing: 6) {
                        ForEach(suggestions) { u in
                            KitLinkButton(title: "@\(u.username)", size: 12) { model.shareName = u.username }
                                .help(u.displayName)
                        }
                    }
                }
                if let reply = model.shareReply {
                    Text(reply.text).font(.system(size: 12)).foregroundStyle(reply.isError ? theme.red400 : theme.green400)
                }
            }
            KitDivider()
            Button { model.shareAsText(bookmark) } label: {
                Label("Share via text message", systemImage: "message").frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(KitButtonStyle(.secondary))
            Button {
                model.copyLink(bookmark)
                copied = true
                Task { try? await Task.sleep(for: .seconds(2)); copied = false }
            } label: {
                Label(copied ? "Copied!" : "Copy link", systemImage: "doc.on.doc").frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(KitButtonStyle(.secondary))
        }
        .padding(16)
        .frame(width: 320)
        .background(theme.surface)
        .environment(\.theme, theme)
    }
}
