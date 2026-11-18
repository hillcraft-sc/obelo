import Foundation

struct ModuleMeta {
    let key: String
    let label: String
    let icon: String

    static let all: [String: ModuleMeta] = [
        "dashboard": .init(key: "dashboard", label: "Today", icon: "house"),
        "capture": .init(key: "capture", label: "Capture", icon: "plus.circle"),
        "notes": .init(key: "notes", label: "Notes", icon: "doc.text"),
        "tasks": .init(key: "tasks", label: "Tasks", icon: "checkmark.circle"),
        "lists": .init(key: "lists", label: "Lists", icon: "list.bullet"),
        "reminders": .init(key: "reminders", label: "Reminders", icon: "bell"),
        "routines": .init(key: "routines", label: "Routines", icon: "arrow.triangle.2.circlepath"),
        "calendar": .init(key: "calendar", label: "Calendar", icon: "calendar"),
        "bookmarks": .init(key: "bookmarks", label: "Bookmarks", icon: "bookmark"),
        "analytics": .init(key: "analytics", label: "Analytics", icon: "chart.bar"),
        "ai": .init(key: "ai", label: "AI Chat", icon: "sparkles"),
        "settings": .init(key: "settings", label: "Settings", icon: "gearshape"),
        "help": .init(key: "help", label: "Help", icon: "questionmark.circle"),
        "search": .init(key: "search", label: "Search", icon: "magnifyingglass"),
    ]

    static func of(_ key: String) -> ModuleMeta { all[key] ?? .init(key: key, label: key.capitalized, icon: "square.grid.2x2") }
}
