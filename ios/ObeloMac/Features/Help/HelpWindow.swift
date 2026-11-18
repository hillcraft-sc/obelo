import SwiftUI

/// What the menu bar can ask of the Help window (Edit ▸ Find)
struct HelpActions {
    let find: () -> Void
}

extension FocusedValues {
    @Entry var helpActions: HelpActions?
}

/// Help: its own window, with the contents on the left and the help text on the right.
/// The text is the server's, shared with the web and the other apps, drawn in the theme's colours.
struct HelpWindow: View {
    @Environment(\.theme) private var theme
    @State private var store = Self.makeStore()
    @State private var focusFind = false

    private static func makeStore() -> HelpStore {
        #if DEBUG
        MacDebug.helpStore()
        #else
        HelpStore()
        #endif
    }

    var body: some View {
        HStack(spacing: 0) {
            KitContentsList(sections: store.sections.map { ($0.id, $0.title) }, current: store.current, onSelect: store.select)
                .frame(width: 200)
            Rectangle().fill(theme.border1).frame(width: 1)
            VStack(alignment: .leading, spacing: 0) {
                header
                content
            }
        }
        .frame(minWidth: 760, minHeight: 480)
        .background(theme.page)
        .task { await store.load() }
        .focusedSceneValue(\.helpActions, HelpActions(find: { focusFind = true }))
    }

    private var header: some View {
        KitPageHeading(title: "Help", description: "A guide to every part of Obelo") {
            HStack(spacing: 4) {
                KitSearchField(placeholder: "Find in Help", text: $store.findQuery, onSubmit: { store.find() }, focusRequest: $focusFind)
                    .frame(width: 200)
                KitIconButton(systemImage: "chevron.up", label: "Previous match") { store.find(backwards: true) }
                KitIconButton(systemImage: "chevron.down", label: "Next match") { store.find() }
            }
        }
        .padding(.horizontal, 28).padding(.top, 24).padding(.bottom, 12)
    }

    @ViewBuilder private var content: some View {
        if let message = store.error, !store.loaded {
            VStack(spacing: 12) {
                KitBanner(kind: .error, text: message)
                Button("Try again") { Task { await store.load() } }.buttonStyle(KitButtonStyle(.secondary))
            }
            .padding(28)
            Spacer()
        } else if store.loaded {
            page.padding(.leading, 24)
        } else {
            KitEmptyState(message: "Loading…")
            Spacer()
        }
    }

    private var page: KitHelpPage {
        var p = KitHelpPage(html: store.html(shortcuts: MacShortcuts.groups), current: $store.current, jump: $store.jump,
                            find: store.findRequest == 0 ? nil : KitHelpFind(id: store.findRequest, text: store.findQuery, backwards: store.findBackwards))
        #if DEBUG
        p.onReady = MacDebug.helpReady
        #endif
        return p
    }
}
