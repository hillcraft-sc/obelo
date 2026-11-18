import SwiftUI

// The wide layout, for the Mac and for iPad at full width: a sidebar with the modules grouped as in
// the redesign plan, and the chosen module beside it. iPhone (and
// iPad in a narrow split) keeps MainShell's top bar and bottom bar.

struct SidebarShell: View {
    @Environment(AppState.self) private var app
    @Environment(Navigator.self) private var nav
    @Environment(\.theme) private var theme
    @State private var paths: [String: NavigationPath] = [:]
    @State private var toast = Toast()

    private var enabled: [String] { app.me?.modules.map(\.key) ?? ["dashboard"] }

    var body: some View {
        @Bindable var nav = nav
        NavigationSplitView {
            List(selection: Binding<String?>(get: { nav.selected }, set: { if let key = $0 { select(key) } })) {
                ForEach(SidebarGroups.groups(enabled: enabled)) { group in
                    if let title = group.title {
                        Section(title) { rows(group.keys) }
                    } else {
                        rows(group.keys)
                    }
                }
                Section {
                    rows(["search", "settings", "help"])
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 280)
            #if os(iOS)
            .navigationTitle("Obelo")
            #endif
        } detail: {
            NavigationStack(path: Binding(get: { paths[nav.selected] ?? NavigationPath() }, set: { paths[nav.selected] = $0 })) {
                root(nav.selected)
                    .navigationDestination(for: Route.self) { RouteView(route: $0) }
            }
            .id(nav.selected)
            .tint(theme.text400)
        }
        .tint(theme.accent)
        .overlay(alignment: .bottom) { ToastOverlay(toast: toast) }
        .environment(toast)
        .onOpenURL { url in
            // From the widget (iPad): obelo://open/today, obelo://open/task/12, …/reminder/3, …/routine/5
            guard url.scheme == "obelo", url.host() == "open" else { return }
            let parts = url.pathComponents.filter { $0 != "/" }
            nav.selected = "dashboard"
            var path = NavigationPath()
            if parts.count == 2, let id = Int(parts[1]) {
                switch parts[0] {
                case "task": path.append(Route.task(id))
                case "reminder": path.append(Route.reminder(id))
                case "routine": path.append(Route.routine(id))
                default: break
                }
            }
            paths["dashboard"] = path
        }
        #if DEBUG
        .onAppear {
            // Testing: `-startTab tasks` opens a screen on launch, `-route note:3` a detail screen
            let d = UserDefaults.standard
            if let tab = d.string(forKey: "startTab") { nav.selected = tab }
            if let route = d.string(forKey: "route") {
                let parts = route.split(separator: ":").map(String.init)
                let id = Int(parts.last ?? "") ?? 0
                switch parts.first {
                case "module": nav.selected = parts.last ?? "dashboard"
                // The detail stack is rebuilt for the new module first, then the screen is pushed
                case "note": nav.selected = "notes"; Task { paths["notes"] = NavigationPath([Route.note(id)]) }
                case "task": nav.selected = "tasks"; Task { paths["tasks"] = NavigationPath([Route.task(id)]) }
                default: break
                }
            }
        }
        #endif
    }

    private func rows(_ keys: [String]) -> some View {
        ForEach(keys, id: \.self) { key in
            let meta = ModuleMeta.of(key)
            Label(meta.label, systemImage: meta.icon).tag(key)
        }
    }

    private func select(_ key: String) {
        // Choosing the current module again goes back to its first screen, like the bottom bar
        if key == nav.selected { paths[key] = NavigationPath() }
        nav.selected = key
    }

    @ViewBuilder private func root(_ key: String) -> some View {
        if key == "search" {
            SearchView()
        } else if key == "notes" {
            // Notes is the three-pane workspace here: tree, note, details
            NotesWorkspace()
                .inlineNavigationTitle()
        } else {
            // The page heading already names the page, so the bar above it doesn't repeat it
            ModuleScreen(key: key)
                .inlineNavigationTitle()
        }
    }
}

/// The Mac menu bar, and the shortcuts a hardware keyboard gets on iPad (hold ⌘ to see them):
/// File ▸ New (⌘N, for the module on screen), Refresh (⌘R), and a Go menu with every sidebar item
/// (⌘1…⌘9, Search ⌘F). Settings is in the app menu (⌘,), as on any Mac app.
struct ObeloCommands: Commands {
    let app: AppState
    let nav: Navigator

    private var enabled: [String] { app.me?.modules.map(\.key) ?? [] }
    private var signedIn: Bool { app.phase == .signedIn }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button(Navigator.newItemLabels[nav.selected] ?? "New") { nav.requestNewItem() }
                .keyboardShortcut("n")
                .disabled(!signedIn || Navigator.newItemLabels[nav.selected] == nil)
        }
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { nav.selected = "settings" }
                .keyboardShortcut(",")
                .disabled(!signedIn)
        }
        CommandGroup(after: .sidebar) {
            Button("Refresh") { app.dataChanged() }
                .keyboardShortcut("r")
                .disabled(!signedIn)
        }
        CommandMenu("Go") {
            let order = SidebarGroups.order(enabled: enabled)
            ForEach(Array(order.enumerated()), id: \.element) { i, key in
                if i < 9 {
                    Button(ModuleMeta.of(key).label) { nav.selected = key }
                        .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")))
                } else {
                    Button(ModuleMeta.of(key).label) { nav.selected = key }
                }
            }
            .disabled(!signedIn)
            Divider()
            Button("Search") { nav.selected = "search" }
                .keyboardShortcut("f")
                .disabled(!signedIn)
            Button("Help") { nav.selected = "help" }
                .keyboardShortcut("?")
                .disabled(!signedIn)
        }
    }
}
