import Foundation

/// Every keyboard shortcut the Mac app has, in one list: the Help window's Keyboard Shortcuts card and the `?`
/// sheet both draw from it. Keep it in step with `MacCommands.swift` (the menus) and `MacSingleKeys`.
enum MacShortcuts {
    static let groups: [ShortcutGroup] = [
        ShortcutGroup(title: "Going places", rows: [
            .init(label: "A module in the sidebar (in its order)", keys: "⌘1 – ⌘9"),
            .init(label: "Search", keys: "⌘K or /"),
            .init(label: "Today", keys: "D"), .init(label: "Tasks", keys: "T"), .init(label: "Capture", keys: "C"),
            .init(label: "New note", keys: "N"), .init(label: "Analytics", keys: "A"), .init(label: "Bookmarks", keys: "B"),
            .init(label: "Help", keys: "H or ⌘?"), .init(label: "This list of shortcuts", keys: "?"),
            .init(label: "Settings", keys: "⌘,"), .init(label: "Back to where you were", keys: "⌘["),
        ]),
        ShortcutGroup(title: "Making and changing", rows: [
            .init(label: "New task, reminder, routine, list, bookmark or event", keys: "⌘N"),
            .init(label: "New note (from anywhere)", keys: "⇧⌘N"), .init(label: "New folder", keys: "⌥⌘N"),
            .init(label: "Edit the selected bookmark or event", keys: "⌘E"), .init(label: "Mark complete", keys: "⌘↩"),
            .init(label: "Delete (asks first)", keys: "⌘⌫"), .init(label: "Find in the list", keys: "⌘F"),
            .init(label: "Clear the AI chat", keys: "⇧⌘⌫"),
        ]),
        ShortcutGroup(title: "Looking at things", rows: [
            .init(label: "Hide or show the sidebar", keys: "⌃⌘S"), .init(label: "Note details", keys: "⌥⌘I"),
            .init(label: "Refresh", keys: "⌘R"),
            .init(label: "Calendar: previous week or month", keys: "⌥⌘←"), .init(label: "Calendar: next week or month", keys: "⌥⌘→"),
            .init(label: "Calendar: today", keys: "⌥⌘T"),
            .init(label: "Analytics: 30 days, 90 days, all time", keys: "⌥⌘1 – ⌥⌘3"),
        ]),
        ShortcutGroup(title: "Writing a note", rows: [
            .init(label: "Bold", keys: "⌘B"), .init(label: "Italic", keys: "⌘I"), .init(label: "Underline", keys: "⌘U"),
            .init(label: "Strikethrough", keys: "⇧⌘X"), .init(label: "Link", keys: "⌘K"),
            .init(label: "Heading 1, 2, 3", keys: "⌥⌘1 – ⌥⌘3"),
        ]),
        ShortcutGroup(title: "Typing and searching", rows: [
            .init(label: "AI Chat: send", keys: "↩"), .init(label: "AI Chat: new line", keys: "⇧↩"),
            .init(label: "Search: move through results", keys: "↑ ↓"), .init(label: "Search: open the result", keys: "↩"),
            .init(label: "Search: close", keys: "Esc"),
        ]),
    ]
}
