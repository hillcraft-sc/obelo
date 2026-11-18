import Foundation

// Storage shared between the app, its share extension and widget (App Group): the server address,
// the session cookie, and a few things the extensions show without fetching (theme, whether AI is on).

enum AppGroup {
    /// Set per build in Signing.xcconfig (ObeloAppGroup in each Info.plist)
    static let id = Bundle.main.object(forInfoDictionaryKey: "ObeloAppGroup") as? String ?? "group.example.obelo"

    #if os(macOS)
    // The Mac app has no extensions yet, so it keeps everything in its own sandboxed storage
    static let defaults = UserDefaults.standard
    static let cookies = HTTPCookieStorage.shared
    #else
    static let defaults = UserDefaults(suiteName: id) ?? .standard
    static let cookies = HTTPCookieStorage.sharedCookieStorage(forGroupContainerIdentifier: id)
    #endif

    private static let appearanceKey = "appearance"
    private static let sessionKey = "sessionCookies"
    private static let aiEnabledKey = "aiEnabled"

    static var appearance: Appearance? {
        get { defaults.data(forKey: appearanceKey).flatMap { try? JSONDecoder().decode(Appearance.self, from: $0) } }
        set { defaults.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: appearanceKey) }
    }

    static var aiEnabled: Bool {
        get { defaults.bool(forKey: aiEnabledKey) }
        set { defaults.set(newValue, forKey: aiEnabledKey) }
    }

    /// The sign-in cookies (name → value) and the host they belong to. Kept here rather than in
    /// a shared HTTPCookieStorage: that one doesn't pass changes between running processes, so
    /// after signing in the widget could keep its old copy and show "signed out".
    static var session: (host: String, cookies: [String: String])? {
        get {
            guard let stored = defaults.dictionary(forKey: sessionKey),
                  let host = stored["host"] as? String,
                  let cookies = stored["cookies"] as? [String: String], !cookies.isEmpty else { return nil }
            return (host, cookies)
        }
        set {
            if let newValue { defaults.set(["host": newValue.host, "cookies": newValue.cookies], forKey: sessionKey) }
            else { defaults.removeObject(forKey: sessionKey) }
        }
    }

    #if !SHARE_EXTENSION
    /// One-time move of the server address and sign-in cookie from the app's private storage
    /// (used before the share extension existed), so nobody has to sign in again.
    static func migrateFromAppStorage() {
        let migratedKey = "migratedToAppGroup"
        guard !defaults.bool(forKey: migratedKey) else { return }
        if defaults.string(forKey: "serverURL") == nil, let server = UserDefaults.standard.string(forKey: "serverURL") {
            defaults.set(server, forKey: "serverURL")
        }
        for cookie in HTTPCookieStorage.shared.cookies ?? [] { cookies.setCookie(cookie) }
        defaults.set(true, forKey: migratedKey)
    }
    #endif
}
