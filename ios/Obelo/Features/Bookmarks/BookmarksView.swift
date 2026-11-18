import SwiftUI

// Bookmarks — views/bookmarks/index.ejs: favicon, title, host, description, tags.

struct BookmarksView: View {
    @Environment(AppState.self) private var app
    @Environment(Toast.self) private var toast
    @Environment(\.theme) private var theme
    @Environment(\.openURL) private var openURL

    struct Response: Decodable { let bookmarks: [Bookmark]; let tags: [String] }

    @State private var tag: String?
    @State private var search = ""
    @State private var data: Response?
    @State private var bookmarks: [Bookmark] = []
    @State private var error: String?
    @State private var editing: Bookmark?
    @State private var showNew = false
    @State private var sharing: Bookmark?

    var body: some View {
        Page(refresh: load) {
            PageHeader(title: "Bookmarks", subtitle: "Saved links, always a click away.", pageName: true) {
                PrimaryButton(title: "New bookmark", systemImage: "plus") { showNew = true }
            }
            ThemedField(placeholder: "Search bookmarks...", text: $search) { Task { await load() } }
                .submitLabel(.search)
            TagFilter(tags: data?.tags ?? [], selected: $tag)
            if let error { Banner(kind: .error, text: error) }
            Card {
                if data == nil {
                    ProgressView().frame(maxWidth: .infinity).padding(40)
                } else if bookmarks.isEmpty {
                    // Same wording as views/bookmarks/index.ejs
                    if tag != nil || !search.isEmpty {
                        EmptyRow(text: "No bookmarks match this filter.", action: EmptyAction(label: "Clear filter") { tag = nil; search = "" })
                    } else {
                        EmptyRow(text: "No bookmarks yet.", action: EmptyAction(label: "New bookmark") { showNew = true })
                    }
                } else {
                    ForEach(Array(bookmarks.enumerated()), id: \.element.id) { i, b in
                        if i > 0 { RowDivider() }
                        SwipeRow(onDelete: { delete(b) }) {
                            row(b)
                        }
                    }
                }
            }
        }
        .task(id: "\(tag ?? "")|\(app.dataVersion)") { await load() }
        .onChange(of: search) { _, new in if new.isEmpty { Task { await load() } } }
        .onNewItem("bookmarks") { showNew = true }
        .sheet(isPresented: $showNew) { BookmarkForm(bookmark: nil) { Task { await load() } } }
        .sheet(item: $editing) { b in BookmarkForm(bookmark: b) { Task { await load() } } }
        .sheet(item: $sharing) { b in BookmarkShareSheet(bookmark: b).presentationDetents([.medium]) }
    }

    private func row(_ b: Bookmark) -> some View {
        HStack(alignment: .top, spacing: 12) {
            AsyncImage(url: URL(string: "https://icons.duckduckgo.com/ip3/\(b.host).ico")) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                Image(systemName: "globe").foregroundStyle(theme.textMuted)
            }
            .frame(width: 16, height: 16).padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                Text(b.displayTitle).font(.system(size: 14, weight: .medium)).foregroundStyle(theme.text100).lineLimit(1)
                Text(b.host).font(.system(size: 12)).foregroundStyle(theme.accentText).lineLimit(1)
                if let d = b.description, !d.isEmpty {
                    Text(d).font(.system(size: 12)).foregroundStyle(theme.textMuted).lineLimit(2)
                }
                if !b.tags.isEmpty {
                    FlowLayout(spacing: 4) { ForEach(b.tags, id: \.self) { TagPill(tag: $0) } }.padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture { if let url = URL(string: b.url) { openURL(url) } }
        .contextMenu {
            Button("Open", systemImage: "safari") { if let url = URL(string: b.url) { openURL(url) } }
            Button("Copy link", systemImage: "doc.on.doc") { Clipboard.copy(b.url); toast.show("Link copied") }
            Button("Send to Obelo user", systemImage: "person.crop.circle.badge.plus") { sharing = b }
            if let url = URL(string: b.url) { ShareLink(item: url) }
            Button("Edit", systemImage: "pencil") { editing = b }
            Button("Delete", systemImage: "trash", role: .destructive) { delete(b) }
        }
    }

    private func load() async {
        do {
            let r: Response = try await APIClient.shared.get("/bookmarks", query: ["tag": tag, "search": search.isEmpty ? nil : search])
            data = r
            withAnimation(.easeOut(duration: 0.15)) { bookmarks = r.bookmarks }
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    private func delete(_ b: Bookmark) {
        withAnimation { bookmarks.removeAll { $0.id == b.id } }
        toast.run { try await APIClient.shared.delete("/bookmarks/\(b.id)"); toast.show("Bookmark deleted") }
    }
}

struct BookmarkForm: View {
    let bookmark: Bookmark?
    let saved: () -> Void

    @State private var url = ""
    @State private var title = ""
    @State private var description = ""
    @State private var tags: [String] = []
    @State private var allTags: [String] = []
    @State private var error: String?
    @State private var loaded = false

    var body: some View {
        FormSheet(title: bookmark == nil ? "Add Bookmark" : "Edit Bookmark", saveTitle: bookmark == nil ? "Add" : "Save",
                  canSave: !url.trimmingCharacters(in: .whitespaces).isEmpty, error: error, save: save) {
            FormSection(label: "URL") {
                ThemedField(placeholder: "https://…", text: $url)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
            }
            FormSection(label: "Title") { ThemedField(placeholder: "Optional", text: $title) }
            FormSection(label: "Description") { ThemedField(placeholder: "Optional", text: $description, axis: .vertical).lineLimit(2...6) }
            FormSection(label: "Tags") { TagsField(tags: $tags, suggestions: allTags) }
        }
        .task {
            guard !loaded else { return }
            loaded = true
            if let b = bookmark {
                url = b.url; title = b.title ?? ""; description = b.description ?? ""; tags = b.tags
            }
            struct T: Decodable { let tags: [String] }
            allTags = ((try? await APIClient.shared.get("/tags")) as T?)?.tags ?? []
        }
    }

    private func save() async -> Bool {
        let body: [String: Any] = ["url": url, "title": title, "description": description, "tags": tags]
        do {
            if let b = bookmark { try await APIClient.shared.post("/bookmarks/\(b.id)", body, method: "PUT") }
            else { try await APIClient.shared.post("/bookmarks", body) }
            saved()
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }
}


/// "Send to Obelo user" (web: the Share Bookmark window): a username with suggestions, and a copy of the bookmark
/// goes to that person
struct BookmarkShareSheet: View {
    let bookmark: Bookmark
    @Environment(Toast.self) private var toast
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var username = ""
    @State private var people: [ListDetail.SharedUser] = []

    private var suggestions: [ListDetail.SharedUser] {
        let q = username.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "@")).lowercased()
        return people.filter { q.isEmpty || $0.username.lowercased().hasPrefix(q) || $0.displayName.lowercased().contains(q) }
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text(bookmark.displayTitle).font(.system(size: 14)).foregroundStyle(theme.text400).lineLimit(1)
                HStack(spacing: 8) {
                    ThemedField(placeholder: "Username", text: $username) { send() }
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    PrimaryButton(title: "Send") { send() }
                }
                ForEach(suggestions.prefix(5)) { u in
                    Button { username = u.username } label: {
                        Text("\(u.displayName) (@\(u.username))").font(.system(size: 14)).foregroundStyle(theme.accentText)
                    }
                }
                Spacer()
            }
            .padding(16)
            .background(theme.page)
            .themedNavBar(theme, title: "Share Bookmark")
            .keyboardDoneButton()
        }
        .presentationBackground(theme.page)
        .task {
            struct U: Decodable { let users: [ListDetail.SharedUser] }
            do { people = (try await APIClient.shared.get("/users/shareable") as U).users }
            catch { toast.show("Couldn't load the people you can send to. \(error.localizedDescription)", error: true) }
        }
    }

    private func send() {
        let name = username.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        struct M: Decodable { let message: String }
        toast.run {
            let r: M = try await APIClient.shared.post("/bookmarks/\(bookmark.id)/share-to-user", ["username": name])
            toast.show(r.message)
            dismiss()
        }
    }
}
