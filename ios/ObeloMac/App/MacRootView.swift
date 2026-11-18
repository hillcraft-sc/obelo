import SwiftUI

/// The window's content: nothing while launching, the sign-in screen, or the shell. The launch, return
/// and midnight handling is the same as the iPhone app's `RootView`.
struct MacRootView: View {
    @Environment(AppState.self) private var app
    @Environment(\.theme) private var theme
    @Environment(\.scenePhase) private var scenePhase
    /// When the app last went to the background
    @State private var leftAt: Date?
    #if DEBUG
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    #endif

    var body: some View {
        ZStack {
            theme.page.ignoresSafeArea()
            switch app.phase {
            case .launching:
                EmptyView()
            case .signedOut:
                MacSignInView().transition(.opacity)
            case .signedIn:
                MacShell()
                    .safeAreaInset(edge: .top) {
                        if let text = ServerVersion.notice(server: app.me?.version) { KitBanner(kind: .warn, text: text).padding(.horizontal, 16) }
                    }
                    .transition(.opacity)
            }
        }
        .toolbar(removing: .title)
        .animation(.easeInOut(duration: 0.25), value: app.phase)
        #if DEBUG
        // Testing: `-openGallery YES` opens the kit gallery on launch
        .onAppear {
            if UserDefaults.standard.bool(forKey: "openGallery") { openWindow(id: "kit-gallery") }
            // `-helpOpen YES` opens the Help window on launch (`-helpSnapshot help.png`, `-helpScroll tasks`, `-helpFind text`)
            if UserDefaults.standard.bool(forKey: "helpOpen") { openWindow(id: "help") }
            // `-settingsOpen YES` opens the Settings window on launch (see MacDebug.PreviewSettingsAPI for the other arguments)
            if UserDefaults.standard.bool(forKey: "settingsOpen") { openSettings() }
        }
        #endif
        // The SSO answer (obelo://auth?code=…) when it arrives as an opened link
        .onOpenURL { app.handleOpenURL($0) }
        // Coming back to the app reloads what's on screen, so Today never shows yesterday
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background: leftAt = .now
            case .active:
                if let leftAt { app.cameBack(leftAt: leftAt) }
                leftAt = nil
            default: break
            }
        }
        // Midnight (or a time zone change) while the app is open
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            if app.phase == .signedIn { app.dataChanged() }
        }
        .task {
            #if DEBUG
            if await MacDebug.previewShellIfAsked(app) { return }
            if await MacDebug.previewSignInIfAsked(app) { return }
            #endif
            await app.restore()
            #if DEBUG
            // Testing: `-devSignIn YES` signs in to a local dev server on launch
            if app.phase == .signedOut, UserDefaults.standard.bool(forKey: "devSignIn") {
                await app.devSignIn(server: APIClient.shared.serverURL.absoluteString)
            }
            #endif
        }
    }
}
