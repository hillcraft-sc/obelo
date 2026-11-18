import Foundation

/// Compares the server's version with the one this app needs. Versions are "major.minor.patch" text, as the
/// server reports them (package.json). Anything that isn't a number counts as 0.
enum ServerVersion {
    /// The oldest server this app build works fully with (the Calendars tab needs 3.55.0)
    static let needed = "3.55.0"

    /// True when `server` is older than `needed`. A server that didn't report a version is not treated as old.
    static func isOlder(_ server: String?, than needed: String = ServerVersion.needed) -> Bool {
        guard let server else { return false }
        let a = parts(server), b = parts(needed)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x < y }
        }
        return false
    }

    private static func parts(_ version: String) -> [Int] {
        version.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
    }

    /// The line shown when the server is older than the app
    static func notice(server: String?) -> String? {
        guard isOlder(server) else { return nil }
        return "Your server is version \(server ?? "?"). This app needs \(needed) or later. Some features won't work until you update the server."
    }
}
