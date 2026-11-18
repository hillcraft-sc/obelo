import SwiftUI

// Lists — views/lists/index.ejs and show.ejs.

struct ListsView: View {
    @Environment(AppState.self) private var app
    @Environment(Toast.self) private var toast
    @Environment(\.theme) private var theme

    struct Response: Decodable { let lists: [ListSummary]; let shared: [ListSummary] }

    @State private var data: Response?
    @State private var error: String?
    @State private var newTitle = ""
    @State private var showNew = false
    @State private var openList: Int?

    var body: some View {
        Page(refresh: load) {
            PageHeader(title: "Lists", subtitle: "Quick, shareable checklists.", pageName: true) {
                PrimaryButton(title: "New list", systemImage: "plus") { showNew = true }
            }
            if let error { Banner(kind: .error, text: error) }
            if let data {
                if data.lists.isEmpty && data.shared.isEmpty {
                    Card { EmptyRow(text: "No lists yet.", action: EmptyAction(label: "New list") { showNew = true }) }
                }
                if !data.lists.isEmpty { section("My Lists", data.lists) }
                if !data.shared.isEmpty { section("Shared with me", data.shared) }
            } else {
                ProgressView().frame(maxWidth: .infinity).padding(40)
            }
        }
        .task(id: app.dataVersion) { await load() }
        .navigationDestination(item: $openList) { ListDetailView(id: $0) }
        .onNewItem("lists") { showNew = true }
        .alert("New list", isPresented: $showNew) {
            TextField("List name", text: $newTitle)
            Button("Cancel", role: .cancel) { newTitle = "" }
            Button("Create") { create() }
        }
    }

    private func section(_ title: String, _ lists: [ListSummary]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).font(.system(size: 12, weight: .semibold)).tracking(1.2)
                .foregroundStyle(theme.textMuted).padding(.horizontal, 4)
            Card {
                ForEach(Array(lists.enumerated()), id: \.element.id) { i, list in
                    if i > 0 { RowDivider() }
                    NavigationLink(value: Route.list(list.id)) {
                        HStack(spacing: 12) {
                            Image(systemName: "list.bullet").font(.system(size: 14)).foregroundStyle(theme.accentText)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(list.title).font(.system(size: 14, weight: .medium)).foregroundStyle(theme.text100)
                                if let owner = list.owner, !list.isOwner {
                                    Text("by \(owner)").font(.system(size: 12)).foregroundStyle(theme.textMuted)
                                }
                            }
                            Spacer()
                            Text("\(list.openCount) open · \(list.itemCount) total").font(.system(size: 12)).foregroundStyle(theme.textMuted)
                            Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(theme.textMuted)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 14)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func load() async {
        do { data = try await APIClient.shared.get("/lists"); error = nil }
        catch { self.error = error.localizedDescription }
    }

    private func create() {
        let title = newTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        newTitle = ""
        toast.run {
            struct R: Decodable { let list: ListSummary }
            let r: R = try await APIClient.shared.post("/lists", ["title": title])
            await load()
            openList = r.list.id
        }
    }
}

struct ListDetailView: View {
    @Environment(AppState.self) private var app
    @Environment(Toast.self) private var toast
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    let id: Int

    struct R: Decodable { let list: ListDetail }

    @State private var list: ListDetail?
    @State private var error: String?
    @State private var newItem = ""
    @State private var editingItem: ListEntry?
    @State private var editText = ""
    @State private var shareName = ""
    @State private var confirmDelete = false
    @State private var showShare = false
    @State private var renaming = false
    @State private var renameText = ""
    @State private var shareable: [ListDetail.SharedUser] = []
    @FocusState private var addFocused: Bool

    var body: some View {
        Loadable(value: list, error: error, retry: load) { list in
            let active = list.items.filter { !$0.checked }
            let done = list.items.filter(\.checked)
            Page(refresh: load) {
                PageHeader(title: list.title, subtitle: list.isOwner ? (list.sharedWith.isEmpty ? nil : "Shared with \(list.sharedWith.map(\.displayName).joined(separator: ", "))") : "Shared by \(list.owner ?? "someone")")
                HStack(spacing: 8) {
                    ThemedField(placeholder: "Add an item…", text: $newItem) { add() }.focused($addFocused)
                    PrimaryButton(title: "Add") { add() }
                }
                Card {
                    if active.isEmpty {
                        EmptyRow(text: done.isEmpty ? "This list is empty." : "All done! 🎉")
                    }
                    ForEach(Array(active.enumerated()), id: \.element.id) { i, item in
                        if i > 0 { RowDivider() }
                        itemRow(item, index: i, count: active.count)
                    }
                }
                if !done.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("DONE · \(done.count)").font(.system(size: 12, weight: .semibold)).tracking(1.2)
                            .foregroundStyle(theme.textMuted).padding(.horizontal, 4)
                        Card {
                            ForEach(Array(done.enumerated()), id: \.element.id) { i, item in
                                if i > 0 { RowDivider() }
                                itemRow(item, index: i, count: done.count)
                            }
                        }
                    }
                }
                HStack {
                    if list.isOwner {
                        SecondaryButton(title: "Share", systemImage: "person.2") { showShare = true }
                        SecondaryButton(title: "Rename", systemImage: "pencil") { renameText = list.title; renaming = true }
                        Spacer()
                        SecondaryButton(title: "Delete list", systemImage: "trash", tint: theme.red400) { confirmDelete = true }
                    }
                }
            }
        }
        .themedNavBar(theme, title: "Lists")
        .task { await load() }
        .alert("Edit item", isPresented: Binding(get: { editingItem != nil }, set: { if !$0 { editingItem = nil } })) {
            TextField("Item", text: $editText)
            Button("Save") { saveEdit() }
            Button("Cancel", role: .cancel) { editingItem = nil }
        }
        .alert("Rename list", isPresented: $renaming) {
            TextField("List name", text: $renameText)
            Button("Save") { rename() }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete this list and all its items?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                toast.run { try await APIClient.shared.delete("/lists/\(id)"); app.dataChanged(); dismiss() }
            }
        }
        .sheet(isPresented: $showShare) {
            shareSheet.presentationDetents([.medium])
                .task {
                    struct U: Decodable { let users: [ListDetail.SharedUser] }
                    guard shareable.isEmpty else { return }
                    do { shareable = (try await APIClient.shared.get("/users/shareable") as U).users }
                    catch { toast.show("Couldn't load the people you can share with. \(error.localizedDescription)", error: true) }
                }
        }
    }

    private func itemRow(_ item: ListEntry, index: Int, count: Int) -> some View {
        SwipeRow(onDelete: { remove(item) }) {
            HStack(spacing: 12) {
                CompleteSquare(done: item.checked) { toggle(item) }
                Text(item.text)
                    .font(.system(size: 14))
                    .strikethrough(item.checked, color: theme.textMuted)
                    .foregroundStyle(item.checked ? theme.textMuted : theme.text200)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { toggle(item) }
                if !item.checked {
                    Menu {
                        Button("Edit", systemImage: "pencil") { editText = item.text; editingItem = item }
                        if index > 0 { Button("Move up", systemImage: "arrow.up") { move(item, by: -1) } }
                        if index < count - 1 { Button("Move down", systemImage: "arrow.down") { move(item, by: 1) } }
                        Button("Delete", systemImage: "trash", role: .destructive) { remove(item) }
                    } label: {
                        Image(systemName: "ellipsis").font(.system(size: 14)).foregroundStyle(theme.textMuted)
                            .frame(width: 32, height: 28).contentShape(Rectangle())
                    }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 11)
        }
    }

    private var shareSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text("People you share with can add, check off and edit items.")
                    .font(.system(size: 14)).foregroundStyle(theme.text400)
                HStack(spacing: 8) {
                    ThemedField(placeholder: "Username", text: $shareName) { share() }
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    PrimaryButton(title: "Share") { share() }
                }
                if !suggestions.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(suggestions) { u in
                            Button { shareName = u.username } label: {
                                Text("\(u.displayName) (@\(u.username))").font(.system(size: 14)).foregroundStyle(theme.accentText)
                            }
                        }
                    }
                }
                ForEach(list?.sharedWith ?? []) { user in
                    HStack {
                        Text(user.displayName).foregroundStyle(theme.text200)
                        Text("@\(user.username)").foregroundStyle(theme.textMuted)
                        Spacer()
                        Button("Remove") {
                            toast.run { try await APIClient.shared.delete("/lists/\(id)/share/\(user.id)"); await load() }
                        }
                        .foregroundStyle(theme.red400)
                    }
                    .font(.system(size: 14))
                }
                Spacer()
            }
            .padding(16)
            .background(theme.page)
            .themedNavBar(theme, title: "Share list")
            .keyboardDoneButton()
        }
        .presentationBackground(theme.page)
    }

    /// People you can pick, not already on the list: everyone when nothing is typed (as the web's list), then
    /// the ones matching what is typed (the same rule the Mac uses)
    private var suggestions: [ListDetail.SharedUser] {
        let q = shareName.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "@")).lowercased()
        let already = Set((list?.sharedWith ?? []).map(\.id))
        return shareable.filter { u in
            !already.contains(u.id) && (q.isEmpty || u.username.lowercased().hasPrefix(q) || u.displayName.lowercased().contains(q))
        }
    }

    private func rename() {
        let title = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title != list?.title else { return }
        toast.run {
            try await APIClient.shared.post("/lists/\(id)", ["title": title], method: "PATCH")
            list?.title = title
            app.dataChanged()
        }
    }

    private func load() async {
        do { list = (try await APIClient.shared.get("/lists/\(id)") as R).list }
        catch { self.error = error.localizedDescription }
    }

    private func add() {
        let text = newItem.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        newItem = ""
        addFocused = true
        toast.run {
            struct I: Decodable { let item: ListEntry }
            let r: I = try await APIClient.shared.post("/lists/\(id)/items", ["text": text])
            withAnimation { list?.items.append(r.item) }
            app.dataChanged()
        }
    }

    private func toggle(_ item: ListEntry) {
        guard let i = list?.items.firstIndex(where: { $0.id == item.id }) else { return }
        withAnimation(.easeOut(duration: 0.2)) { list?.items[i].checked.toggle() }
        toast.run { try await APIClient.shared.post("/lists/\(id)/items/\(item.id)/toggle"); app.dataChanged() }
    }

    private func remove(_ item: ListEntry) {
        withAnimation { list?.items.removeAll { $0.id == item.id } }
        toast.run { try await APIClient.shared.delete("/lists/\(id)/items/\(item.id)"); app.dataChanged() }
    }

    private func saveEdit() {
        guard let item = editingItem else { return }
        let text = editText.trimmingCharacters(in: .whitespaces)
        editingItem = nil
        guard !text.isEmpty, let i = list?.items.firstIndex(where: { $0.id == item.id }) else { return }
        list?.items[i].text = text
        toast.run { try await APIClient.shared.post("/lists/\(id)/items/\(item.id)", ["text": text], method: "PATCH") }
    }

    private func move(_ item: ListEntry, by delta: Int) {
        guard var active = list?.items.filter({ !$0.checked }),
              let from = active.firstIndex(where: { $0.id == item.id }) else { return }
        let to = from + delta
        guard active.indices.contains(to) else { return }
        active.swapAt(from, to)
        let done = list?.items.filter(\.checked) ?? []
        withAnimation { list?.items = active + done }
        toast.run { try await APIClient.shared.post("/lists/\(id)/items/reorder", ["ids": active.map(\.id)]) }
    }

    private func share() {
        let name = shareName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        toast.run {
            try await APIClient.shared.post("/lists/\(id)/share", ["username": name])
            shareName = ""
            toast.show("Shared with @\(name)")
            await load()
        }
    }
}
