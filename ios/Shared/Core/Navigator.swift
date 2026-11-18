import SwiftUI

/// Which screen the wide layout shows, and "new item" requests from the menu bar (⌘N)
@Observable
final class Navigator {
    var selected = "dashboard"
    /// The Mac's search palette is open (it sits over whatever screen is showing)
    var searchOpen = false
    /// The Mac's Help window was asked for (a counter, so every ask is seen) and its `?` shortcut sheet is open
    var helpRequest = 0
    var shortcutsOpen = false
    var newItem: NewItemRequest?

    struct NewItemRequest: Equatable {
        let key: String
        let id = UUID()
    }

    /// The modules that make something with ⌘N, and what the menu calls it
    static let newItemLabels: [String: String] = [
        "tasks": "New Task", "reminders": "New Reminder", "routines": "New Routine", "notes": "New Note",
        "lists": "New List", "bookmarks": "New Bookmark", "calendar": "New Event",
    ]

    func requestNewItem() {
        guard Self.newItemLabels[selected] != nil else { return }
        newItem = NewItemRequest(key: selected)
    }
}

extension View {
    /// Runs `action` when the menu bar asks for a new item on this module's screen (⌘N)
    func onNewItem(_ key: String, perform action: @escaping () -> Void) -> some View {
        modifier(NewItemModifier(key: key, action: action))
    }
}

private struct NewItemModifier: ViewModifier {
    @Environment(Navigator.self) private var nav: Navigator?
    let key: String
    let action: () -> Void

    func body(content: Content) -> some View {
        content.onChange(of: nav?.newItem) { _, request in
            guard let request, request.key == key else { return }
            nav?.newItem = nil
            action()
        }
    }
}
