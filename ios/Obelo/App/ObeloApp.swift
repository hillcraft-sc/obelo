import Combine
import SwiftUI

@main
struct ObeloApp: App {
    @State private var app = AppState()
    @State private var nav = Navigator()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .environment(nav)
                .environment(\.theme, app.theme)
                .preferredColorScheme(app.theme.colorScheme)
                .tint(app.theme.accent)
        }
        .commands { ObeloCommands(app: app, nav: nav) }
    }
}

struct RootView: View {
    #if os(iOS)
    private static let timeChange = UIApplication.significantTimeChangeNotification
    #else
    private static let timeChange = Notification.Name.NSCalendarDayChanged
    #endif

    @Environment(AppState.self) private var app
    @Environment(\.theme) private var theme
    @Environment(\.scenePhase) private var scenePhase
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif
    /// When the app last went to the background
    @State private var leftAt: Date?

    /// The sidebar layout: always on the Mac, and on iPad when the app has the full width
    private var wide: Bool {
        #if os(iOS)
        sizeClass == .regular
        #else
        true
        #endif
    }

    var body: some View {
        ZStack {
            theme.page.ignoresSafeArea()
            switch app.phase {
            case .launching:
                EmptyView()
            case .signedOut:
                LoginView().transition(.opacity)
            case .signedIn:
                Group {
                    if wide { SidebarShell() } else { MainShell() }
                }
                .safeAreaInset(edge: .top) {
                    if let text = ServerVersion.notice(server: app.me?.version) { Banner(kind: .warning, text: text).padding(.horizontal, 16) }
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: app.phase)
        // The SSO answer (obelo://auth?code=…) when it arrives as an opened link (Mac browsers)
        .onOpenURL { app.handleOpenURL($0) }
        .onAppear { Keyboard.installTapToDismiss() }
        // Coming back to the app reloads what's on screen, so Today never shows yesterday (issue #8)
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
        .onReceive(NotificationCenter.default.publisher(for: Self.timeChange)) { _ in
            if app.phase == .signedIn { app.dataChanged() }
        }
        .task {
            await app.restore()
            #if DEBUG
            // Simulator testing: `-devSignIn YES` signs in to a local dev server on launch
            if app.phase == .signedOut, UserDefaults.standard.bool(forKey: "devSignIn") {
                await app.devSignIn(server: APIClient.shared.serverURL.absoluteString)
            }
            #endif
        }
    }
}
