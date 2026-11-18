import SwiftUI

// The Mac app's entry point. The iPhone app's `ObeloApp` is not compiled into this target.

@main
struct ObeloMacApp: App {
    @State private var app = AppState()
    @State private var nav: Navigator
    @State private var router: MacRouter

    init() {
        let navigator = Navigator()
        _nav = State(initialValue: navigator)
        _router = State(initialValue: MacRouter(nav: navigator))
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            MacRootView()
                .environment(app)
                .environment(nav)
                .environment(router)
                .environment(\.theme, app.theme)
                .preferredColorScheme(app.theme.colorScheme)
                .tint(app.theme.accent)
                .frame(minWidth: 900, minHeight: 600)
                .background(MacWindowConfigurator(page: app.theme.page))
        }
        .defaultSize(width: 1280, height: 840)
        .windowResizability(.contentMinSize)
        .commands { MacCommands(app: app, nav: nav) }

        // Settings: its own window with a toolbar of tabs, opened with ⌘, and from the gear in the sidebar
        Settings {
            SettingsWindow()
                .environment(app)
                .environment(\.theme, app.theme)
                .preferredColorScheme(app.theme.colorScheme)
                .tint(app.theme.accent)
        }

        // Help: its own window, opened from the Help menu, the sidebar and the H key
        Window("Help", id: "help") {
            HelpWindow()
                .environment(app)
                .environment(\.theme, app.theme)
                .preferredColorScheme(app.theme.colorScheme)
                .tint(app.theme.accent)
        }
        .defaultSize(width: 980, height: 760)

        #if DEBUG
        // The kit gallery: every design-kit component in every theme and state (Debug ▸ Kit Gallery)
        Window("Kit Gallery", id: "kit-gallery") {
            KitGallery()
        }
        .defaultSize(width: 980, height: 900)
        #endif
    }
}
