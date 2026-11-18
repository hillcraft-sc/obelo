import Foundation

/// The sidebar groups from the redesign plan: Today and Capture first, then Do, Write, Plan, See and Assist.
/// Only modules the user has switched on appear, and each group has a fixed order, so the sidebar looks the same
/// on the web, the Mac and a wide iPad. (The saved module order only decides the iPhone's bottom bar.)
enum SidebarGroups {
    struct Group: Identifiable, Equatable {
        let title: String?
        let keys: [String]
        var id: String { title ?? keys.joined() }
    }

    static let layout: [(String?, [String])] = [
        (nil, ["dashboard", "capture"]),
        ("Do", ["tasks", "reminders", "routines"]),
        ("Write", ["notes", "lists", "bookmarks"]),
        ("Plan", ["calendar"]),
        ("See", ["analytics"]),
        ("Assist", ["ai"]),
    ]

    static func groups(enabled: [String]) -> [Group] {
        let placed = Set(layout.flatMap(\.1))
        var groups = layout.compactMap { title, keys -> Group? in
            let shown = keys.filter { enabled.contains($0) }
            return shown.isEmpty ? nil : Group(title: title, keys: shown)
        }
        // A module the plan doesn't place yet still gets a home
        let other = enabled.filter { !placed.contains($0) && $0 != "settings" }
        if !other.isEmpty { groups.append(Group(title: "More", keys: other)) }
        return groups
    }

    /// Where a module sits in the sidebar, for listing modules in that order (Today first, Settings last)
    static func sortRank(_ key: String) -> Int {
        if key == "dashboard" { return -1 }
        if key == "settings" { return 1000 }
        return layout.flatMap(\.1).firstIndex(of: key) ?? 500
    }

    /// Everything in the sidebar, top to bottom (for ⌘1…⌘9)
    static func order(enabled: [String]) -> [String] {
        groups(enabled: enabled).flatMap(\.keys)
    }
}
