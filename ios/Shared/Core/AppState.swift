import AuthenticationServices
import SwiftUI
import WidgetKit

// App-wide state: who is signed in, their appearance, and which modules they use.

@Observable
final class AppState {
    enum Phase { case launching, signedOut, signedIn }

    var phase: Phase = .launching
    var me: Me?
    var theme: Theme = .darkDefault
    var signInError: String?
    var signingIn = false

    /// Bumped whenever data changes somewhere that other screens show (e.g. completing a task
    /// from Today), so visible lists reload, like the web does on navigation.
    var dataVersion = 0

    private let api = APIClient.shared

    init() {
        AppGroup.migrateFromAppStorage()
        NotificationCenter.default.addObserver(forName: APIClient.unauthorizedNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.phase == .signedIn else { return }
                self.phase = .signedOut
                self.me = nil
            }
        }
    }

    var hour12: Bool { me?.hour12 ?? true }

    func dataChanged() { dataVersion += 1 }

    /// The app is back in front. Reload on a new day, or after more than a minute away, since the
    /// web, the widget or another device may have changed things meanwhile.
    func cameBack(leftAt: Date, now: Date = .now) {
        guard phase == .signedIn else { return }
        if !Calendar.current.isDate(leftAt, inSameDayAs: now) || now.timeIntervalSince(leftAt) > 60 { dataChanged() }
    }

    func isEnabled(_ module: String) -> Bool {
        me?.modules.contains { $0.key == module } ?? false
    }

    // ── Session ──────────────────────────────────────────────────────────────

    func restore() async {
        do {
            try await loadMe()
            phase = .signedIn
        } catch {
            phase = .signedOut
        }
        // The widget may still show what it saw before (e.g. signed out); bring it in line
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// The paper handwriting is drawn on (Settings > Notes, "Handwriting paper")
    var drawingPaper: DrawingPaper { DrawingPaper.resolve(me?.notePaper, theme: theme) }

    func loadMe() async throws {
        let me: Me = try await api.get("/me")
        self.me = me
        AppGroup.appearance = me.appearance
        AppGroup.aiEnabled = me.aiEnabled
        withAnimation(.easeInOut(duration: 0.2)) { theme = Theme.resolve(me.appearance) }
    }

    /// The sign-in sheet waiting for the server's obelo://auth?code=… answer
    private var authSession: ASWebAuthenticationSession?

    /// SSO in the system auth sheet; the server answers with obelo://auth?code=…
    func signIn(server: String, anchor: ASPresentationAnchor) async {
        signInError = nil
        guard let base = normalizedServer(server) else {
            signInError = "Enter your Obelo address, like https://obelo.example.com"
            return
        }
        api.serverURL = base
        signingIn = true
        defer { signingIn = false }

        var start = URLComponents(url: base.appending(path: "/auth/oidc"), resolvingAgainstBaseURL: false)!
        start.queryItems = [URLQueryItem(name: "client", value: "ios")]

        do {
            let callback = try await WebAuth.run(url: start.url!, callbackScheme: "obelo", anchor: anchor) { self.authSession = $0 }
            authSession = nil
            await finishSignIn(callback)
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            // The person closed the sheet, or the answer arrived as an opened link (handleOpenURL)
            authSession = nil
        } catch {
            authSession = nil
            signInError = error.localizedDescription
        }
    }

    /// On the Mac the sign-in can finish in the person's own browser, which hands obelo://auth?code=…
    /// to the app as an opened link rather than back to the waiting sheet. Finish signing in from it,
    /// and close the sheet that's still waiting.
    func handleOpenURL(_ url: URL) {
        guard url.scheme == "obelo", url.host() == "auth", phase == .signedOut else { return }
        authSession?.cancel()
        authSession = nil
        Task { await finishSignIn(url) }
    }

    /// Trades the one-time code in the server's obelo://auth?code=… answer for a session
    private func finishSignIn(_ callback: URL) async {
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard let code = items.first(where: { $0.name == "code" })?.value else {
            signInError = "Sign-in didn't complete. Please try again."
            return
        }
        signingIn = true
        defer { signingIn = false }
        do {
            try await api.post("/auth/exchange", ["code": code])
            try await loadMe()
            phase = .signedIn
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            signInError = error.localizedDescription
        }
    }

    /// Username (or email) and password. The server answers with the same kind of session as SSO
    func passwordSignIn(server: String, username: String, password: String) async {
        signInError = nil
        guard let base = normalizedServer(server) else {
            signInError = "Enter your Obelo address, like https://obelo.example.com"
            return
        }
        api.serverURL = base
        signingIn = true
        defer { signingIn = false }
        do {
            try await api.post("/auth/login", ["username": username, "password": password])
            try await loadMe()
            phase = .signedIn
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            signInError = error.localizedDescription
        }
    }

    /// Chooses a password with the setup code an admin gave you, then signs in with it.
    /// Returns an error to show, or nil when signed in.
    func setPasswordWithCode(server: String, username: String, code: String, password: String) async -> String? {
        guard let base = normalizedServer(server) else {
            return "Enter your Obelo address, like https://obelo.example.com"
        }
        api.serverURL = base
        do {
            try await api.post("/auth/password-code", ["username": username, "code": code, "newPassword": password])
        } catch {
            return error.localizedDescription
        }
        await passwordSignIn(server: server, username: username, password: password)
        return signInError
    }

    #if DEBUG
    /// Local development only (server must run with NODE_ENV=development and DEV_APP_LOGIN_USER)
    func devSignIn(server: String) async {
        signInError = nil
        guard let base = normalizedServer(server) else { return }
        api.serverURL = base
        do {
            try await api.post("/auth/dev")
            try await loadMe()
            phase = .signedIn
        } catch {
            signInError = error.localizedDescription
        }
    }
    #endif

    func signOut() async {
        try? await api.post("/auth/logout")
        api.clearCookies()
        me = nil
        phase = .signedOut
        WidgetCenter.shared.reloadAllTimelines()
    }

    func setTheme(_ id: String) async {
        guard var me else { return }
        me.appearance.theme = id
        me.appearance.isDark = Theme.resolve(me.appearance).isDark
        self.me = me
        AppGroup.appearance = me.appearance
        withAnimation(.easeInOut(duration: 0.2)) { theme = Theme.resolve(me.appearance) }
        try? await api.post("/me/appearance", ["theme": id])
    }

    private func normalizedServer(_ raw: String) -> URL? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return nil }
        if !s.contains("://") { s = "https://" + s }
        while s.hasSuffix("/") { s.removeLast() }
        guard let url = URL(string: s), url.host() != nil else { return nil }
        return url
    }
}

/// async wrapper around ASWebAuthenticationSession
enum WebAuth {
    final class ContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
        let anchor: ASPresentationAnchor
        init(anchor: ASPresentationAnchor) { self.anchor = anchor }
        func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor { anchor }
    }

    static func run(url: URL, callbackScheme: String, anchor: ASPresentationAnchor,
                    started: (ASWebAuthenticationSession) -> Void = { _ in }) async throws -> URL {
        #if os(macOS)
        // On the Mac the system session opens the default browser, and third-party browsers (Brave,
        // for one) take the sign-in but never hand obelo://auth back. The app's own sheet always can.
        return try await MacSignInSheet.run(url: url, callbackScheme: callbackScheme, parent: anchor)
        #else
        let provider = ContextProvider(anchor: anchor)
        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callback: .customScheme(callbackScheme)) { callback, error in
                // presentationContextProvider is weak: this capture keeps the provider alive until we finish
                withExtendedLifetime(provider) {
                    if let callback { continuation.resume(returning: callback) }
                    else { continuation.resume(throwing: error ?? ASWebAuthenticationSessionError(.canceledLogin)) }
                }
            }
            session.presentationContextProvider = provider
            // Share the Safari cookie jar so an existing SSO sign-in is reused
            session.prefersEphemeralWebBrowserSession = false
            started(session)
            session.start()
        }
        #endif
    }
}
