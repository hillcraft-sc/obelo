import SwiftUI

/// Search: a centred palette over whatever screen is showing. ⌘K, `/`, the sidebar's
/// Search box and Go ▸ Search open it. Return or a click opens the result inside the app, and Back in the title
/// bar returns to where you were.
struct SearchPalette: View {
    @Environment(Navigator.self) private var nav
    @Environment(MacRouter.self) private var router
    @Environment(\.theme) private var theme
    @State private var store = Self.makeStore()

    private static func makeStore() -> SearchStore {
        #if DEBUG
        MacDebug.searchStore()
        #else
        SearchStore()
        #endif
    }

    var body: some View {
        KitPalette(onClose: close) {
            KitPaletteField(placeholder: "Search notes, tasks, lists, bookmarks…", text: $store.query,
                            onMove: { store.move($0) }, onSubmit: openCurrent, onEscape: close)
            results
            footer
        }
        .onKeyPress(.escape) { close(); return .handled }
        #if DEBUG
        .task {
            // Testing: `-searchQuery trip` types that, `-searchDown 2` moves the highlight down
            if let q = UserDefaults.standard.string(forKey: "searchQuery") {
                store.query = q
                await store.settle()
                store.move(UserDefaults.standard.integer(forKey: "searchDown"))
            }
        }
        #endif
    }

    // ── Results ─────────────────────────────────────────────────────────────

    private func key(_ hit: SearchResponse.Hit) -> String { "\(hit.type)-\(hit.id)" }

    @ViewBuilder private var results: some View {
        if let message = store.message {
            Text(message).font(.system(size: 14)).foregroundStyle(theme.textMuted)
                .frame(maxWidth: .infinity).padding(.vertical, 24).padding(.horizontal, 16)
                .accessibilityLabel(message)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(store.groups) { group in
                            VStack(alignment: .leading, spacing: 2) {
                                KitGroupLabel(text: group.group).padding(.horizontal, 8).padding(.bottom, 2)
                                ForEach(group.items, id: \.self) { hit in
                                    KitSearchRow(icon: SearchStore.icon(for: hit.type),
                                                 title: SearchStore.pieces(of: hit.title, matching: store.trimmed),
                                                 subtitle: hit.subtitle, isHighlighted: store.current == hit,
                                                 onOpen: { open(hit) })
                                        .id(key(hit))
                                }
                            }
                            .padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 4)
                        }
                    }
                    .padding(.bottom, 8)
                }
                .onChange(of: store.highlighted) {
                    if let hit = store.current { withAnimation(.easeOut(duration: 0.1)) { proxy.scrollTo(key(hit)) } }
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 16) {
            hint("↑↓", "navigate"); hint("↵", "open"); hint("Esc", "close")
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .overlay(alignment: .top) { Rectangle().fill(theme.border1).frame(height: 1) }
    }

    private func hint(_ keys: String, _ word: String) -> some View {
        HStack(spacing: 4) {
            Text(keys).font(.system(size: 10, design: .monospaced))
            Text(word).font(.system(size: 10))
        }
        .foregroundStyle(theme.textMuted)
    }

    // ── Actions ─────────────────────────────────────────────────────────────

    private func close() {
        store.reset()
        nav.searchOpen = false
    }

    private func openCurrent() {
        if let hit = store.current { open(hit) }
    }

    private func open(_ hit: SearchResponse.Hit) {
        let destination: MacRouter.Destination?
        switch hit.type {
        case "note": destination = .note(hit.id)
        case "task": destination = .tasks(view: nil, task: hit.id)
        case "reminder": destination = .reminder(hit.id)
        case "routine": destination = .routine(hit.id)
        case "list": destination = .list(hit.id)
        case "bookmark": destination = .bookmark(hit.id)
        default: destination = nil
        }
        let search = store
        close()
        if let destination { router.open(destination); return }
        if hit.type == "calendar" {
            Task { if let event = await search.event(id: hit.id) { router.open(.event(event)) } else { router.open(.module("calendar")) } }
        }
    }
}
