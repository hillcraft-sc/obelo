import SwiftUI

/// The signed-in window: the sidebar on the left (256 wide, like the web's), the module's screen beside it.
/// `Navigator` (in `Shared/`) holds which module is showing.
struct MacShell: View {
    @Environment(AppState.self) private var app
    @Environment(Navigator.self) private var nav
    @Environment(\.openWindow) private var openWindow
    @Environment(\.theme) private var theme
    @AppStorage("macSidebarVisible") private var sidebarVisible = true
    @Environment(MacRouter.self) private var router
    @State private var toast = KitToastCenter()
    @State private var keyMonitor: Any?
    /// Kept here so a draft survives a visit to another screen
    @State private var captureStore = MacShell.makeCaptureStore()

    private var enabled: [String] { app.me?.modules.map(\.key) ?? ["dashboard"] }

    var body: some View {
        HStack(spacing: 0) {
            if sidebarVisible {
                MacSidebar()
                    .frame(width: 256)
                    .transition(.move(edge: .leading))
            }
            screen
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(theme.page.ignoresSafeArea())
        .animation(.easeInOut(duration: 0.18), value: sidebarVisible)
        // Going somewhere else by hand (sidebar, menu, a key) forgets where you came from
        .onChange(of: nav.selected) { _, selected in
            if let origin = router.origin, origin.to != selected { router.origin = nil }
        }
        .onChange(of: nav.helpRequest) { openWindow(id: "help") }
        .sheet(isPresented: Bindable(nav).shortcutsOpen) { ShortcutsSheet() }
        .overlay { if nav.searchOpen { SearchPalette().transition(.opacity) } }
        .animation(.easeOut(duration: 0.12), value: nav.searchOpen)
        .overlay(alignment: .bottom) { KitToastOverlay(center: toast) }
        .environment(toast)
        .onAppear {
            keyMonitor = MacSingleKeys.install(nav: nav) { enabled }
            #if DEBUG
            applyLaunchArguments()
            #endif
        }
        .onDisappear {
            if let keyMonitor { MacSingleKeys.remove(keyMonitor) }
            keyMonitor = nil
        }
    }

    /// The module's screen: one case per module
    @ViewBuilder private var screen: some View {
        switch nav.selected {
        case "dashboard":
            TodayScreen().modifier(MacScreenChrome(module: "dashboard"))
        case "notes":
            NotesScreen().modifier(MacScreenChrome(module: "notes"))
        case "capture":
            CaptureScreen(store: captureStore).modifier(MacScreenChrome(module: "capture"))
        case "tasks":
            TasksScreen().modifier(MacScreenChrome(module: "tasks"))
        case "reminders":
            RemindersScreen().modifier(MacScreenChrome(module: "reminders"))
        case "routines":
            RoutinesScreen().modifier(MacScreenChrome(module: "routines"))
        case "lists":
            ListsScreen().modifier(MacScreenChrome(module: "lists"))
        case "calendar":
            CalendarScreen().modifier(MacScreenChrome(module: "calendar"))
        case "ai":
            AIChatScreen().modifier(MacScreenChrome(module: "ai"))
        case "analytics":
            AnalyticsScreen().modifier(MacScreenChrome(module: "analytics"))
        case "bookmarks":
            BookmarksScreen().modifier(MacScreenChrome(module: "bookmarks"))
        default:
            // Settings and Help open in their own windows; anything else unknown shows Today
            TodayScreen().modifier(MacScreenChrome(module: "dashboard"))
        }
    }

    private static func makeCaptureStore() -> CaptureStore {
        #if DEBUG
        MacDebug.captureStore()
        #else
        CaptureStore()
        #endif
    }

    #if DEBUG
    /// Testing: `-startTab tasks` opens a module on launch, `-route note:3`, `task:3` or `reminder:3` a detail screen, `-backFrom dashboard` as if it was opened from Today
    private func applyLaunchArguments() {
        let d = UserDefaults.standard
        if let tab = d.string(forKey: "startTab") { nav.selected = tab }
        // `-searchOpen YES` opens the search palette (with `-searchQuery trip`, `-searchDown 2`, `-searchSample empty|fail`)
        if d.bool(forKey: "searchOpen") { nav.searchOpen = true }
        if let from = d.string(forKey: "backFrom") { router.origin = MacRouter.Origin(from: from, to: nav.selected) }
        guard let route = d.string(forKey: "route") else { return }
        let parts = route.split(separator: ":").map(String.init)
        let id = Int(parts.last ?? "") ?? 0
        switch parts.first {
        case "module": nav.selected = parts.last ?? "dashboard"
        case "note": router.open(.note(id))
        case "task": router.open(.tasks(view: nil, task: id))
        case "reminder": nav.selected = "reminders"; router.remindersRequest = id
        case "routine": nav.selected = "routines"; router.routinesRequest = id
        case "list": nav.selected = "lists"; router.listsRequest = id
        default: break
        }
    }
    #endif
}

/// "‹ Back" in the kit's ghost style, with ⌘[ like Safari and Finder
struct MacBackButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold))
                Text("Back")
            }
        }
        .buttonStyle(KitButtonStyle(.ghost, small: true))
        .keyboardShortcut("[", modifiers: .command)
        .help("Back (⌘[)")
        .accessibilityLabel("Back")
    }
}

/// The title bar above a Mac screen: no window title, no bar background, and Back (a real toolbar item, so
/// it takes clicks, like the old screens' Back) when this screen was opened from another one. Every screen
/// has a toolbar, so the title bar is the same height on all of them.
private struct MacScreenChrome: ViewModifier {
    @Environment(MacRouter.self) private var router
    let module: String

    func body(content: Content) -> some View {
        content
            .toolbar(removing: .title)
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    if router.origin?.to == module {
                        MacBackButton { router.goBack(in: module) }
                    } else {
                        // Keeps the title bar the same height with or without Back, so the window buttons never move
                        Color.clear.frame(width: 1, height: 28).accessibilityHidden(true)
                    }
                }
                .sharedBackgroundVisibility(.hidden)
            }
    }
}
