import SwiftUI

// Global search — partials/search-modal.ejs, backed by the same /search endpoint.

struct SearchView: View {
    @Environment(\.theme) private var theme
    @State private var query = ""
    @State private var groups: [SearchResponse.Group] = []
    @State private var searching = false
    @FocusState private var focused: Bool

    private static let icons = [
        "note": "doc.text", "task": "checkmark.circle", "reminder": "bell", "routine": "arrow.triangle.2.circlepath",
        "calendar": "calendar", "list": "list.bullet", "bookmark": "bookmark",
    ]

    var body: some View {
        Page {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(theme.textMuted)
                TextField("", text: $query, prompt: Text("Search everything…").foregroundStyle(theme.placeholder))
                    .focused($focused)
                    .foregroundStyle(theme.text100)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                if searching { ProgressView().controlSize(.small) }
            }
            .font(.system(size: 16))
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(theme.elevated, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(focused ? theme.accent : theme.border2, lineWidth: focused ? 2 : 1))

            if query.count >= 2, groups.isEmpty, !searching {
                Card { EmptyRow(text: "No results for “\(query)”.") }
            }
            ForEach(groups) { group in
                Card {
                    CardHeader(title: group.group)
                    ForEach(Array(group.items.enumerated()), id: \.element) { i, hit in
                        if i > 0 { RowDivider() }
                        NavigationLink(value: route(for: hit)) {
                            HStack(spacing: 12) {
                                Image(systemName: Self.icons[hit.type] ?? "circle").font(.system(size: 14))
                                    .foregroundStyle(theme.accentText).frame(width: 20)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(hit.title).font(.system(size: 14)).foregroundStyle(theme.text200).lineLimit(1)
                                    if let sub = hit.subtitle { Text(sub).font(.system(size: 12)).foregroundStyle(theme.textMuted).lineLimit(1) }
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(theme.textMuted)
                            }
                            .padding(.horizontal, 16).padding(.vertical, 11)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .themedNavBar(theme, title: "Search")
        .navigationBarVisibility(.visible)
        .onAppear { focused = true }
        .task(id: query) {
            let q = query.trimmingCharacters(in: .whitespaces)
            guard q.count >= 2 else { groups = []; return }
            try? await Task.sleep(for: .milliseconds(250)) // debounce while typing
            guard !Task.isCancelled else { return }
            searching = true
            defer { searching = false }
            if let r: SearchResponse = try? await APIClient.shared.get("/search", query: ["q": q]) {
                withAnimation(.easeOut(duration: 0.15)) { groups = r.results }
            }
        }
    }

    private func route(for hit: SearchResponse.Hit) -> Route {
        switch hit.type {
        case "note": .note(hit.id)
        case "task": .task(hit.id)
        case "reminder": .reminder(hit.id)
        case "routine": .routine(hit.id)
        case "list": .list(hit.id)
        case "calendar": .eventID(hit.id)
        default: .module("bookmarks")
        }
    }
}
