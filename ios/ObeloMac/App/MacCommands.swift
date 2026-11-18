import AppKit
import SwiftUI

/// The menu bar. File: the module's New item (⌘N) and New Note (⇧⌘N). View: sidebar, refresh. Go: every
/// sidebar item (⌘1–⌘9) and Search (⌘K). Help: Obelo Help. Edit and Window are the system's.
/// Find (⌘F), Mark Complete (⌘↩) and Delete (⌘⌫) work while a screen offers them (Tasks, Reminders, Routines, Notes). On the Notes screen
/// there is a Format menu (⌘B, ⌘I, ⌘U, ⇧⌘X, ⌘K for Link, ⌥⌘1–3 for headings), New Folder (⌥⌘N) and View ▸ Toggle
/// Details (⌘⌥I). ⌘K is Link there and Search elsewhere (Search stays in the sidebar and on "/").
struct MacCommands: Commands {
    let app: AppState
    let nav: Navigator
    @AppStorage("macSidebarVisible") private var sidebarVisible = true
    @FocusedValue(\.tasksActions) private var tasks
    @FocusedValue(\.remindersActions) private var reminders
    @FocusedValue(\.routinesActions) private var routines
    @FocusedValue(\.listsActions) private var lists
    @FocusedValue(\.bookmarksActions) private var bookmarks
    @FocusedValue(\.calendarActions) private var calendar
    @FocusedValue(\.analyticsActions) private var analytics
    @FocusedValue(\.chatActions) private var chat
    @FocusedValue(\.helpActions) private var help
    @FocusedValue(\.notesActions) private var notes
    @Environment(\.openWindow) private var openWindow

    private var enabled: [String] { app.me?.modules.map(\.key) ?? [] }
    private var signedIn: Bool { app.phase == .signedIn }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button(Navigator.newItemLabels[nav.selected] ?? "New Item") { nav.requestNewItem() }
                .keyboardShortcut("n")
                .disabled(!signedIn || Navigator.newItemLabels[nav.selected] == nil)
            Button("New Note") { newNote() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(!signedIn || !enabled.contains("notes"))
            Divider()
            Button("Mark Complete") { if let routines { routines.complete() } else if let reminders { reminders.complete() } else { tasks?.complete() } }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(tasks == nil && reminders == nil && routines == nil)
            Button("Delete") { if let calendar { calendar.delete() } else if let bookmarks { bookmarks.delete() } else if let lists { lists.delete() } else if let routines { routines.delete() } else if let reminders { reminders.delete() } else { tasks?.delete() } }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(tasks == nil && reminders == nil && routines == nil && lists == nil && bookmarks == nil && calendar == nil)
        }
        CommandGroup(after: .newItem) {
            Button(calendar != nil ? "Edit Event" : "Edit Bookmark") { if let calendar { calendar.edit() } else { bookmarks?.edit() } }
                .keyboardShortcut("e")
                .disabled(bookmarks == nil && calendar == nil)
            Button("Clear Chat…") { chat?.clear() }
                .keyboardShortcut(.delete, modifiers: [.command, .shift])
                .disabled(chat == nil)
            Button("New Folder") { notes?.newFolder() }
                .keyboardShortcut("n", modifiers: [.command, .option])
                .disabled(notes == nil)
        }
        CommandGroup(after: .textEditing) {
            Button("Find") { if let help { help.find() } else if let notes { notes.find() } else if let bookmarks { bookmarks.find() } else { tasks?.find() } }
                .keyboardShortcut("f")
                .disabled(tasks == nil && notes == nil && bookmarks == nil && help == nil)
        }
        CommandMenu("Format") {
            Group {
                formatItem(.bold, "b")
                formatItem(.italic, "i")
                formatItem(.underline, "u")
                formatItem(.strike, "x", [.command, .shift])
                Divider()
                formatItem(.h1, "1", [.command, .option])
                formatItem(.h2, "2", [.command, .option])
                formatItem(.h3, "3", [.command, .option])
                Divider()
                formatItem(.ul)
                formatItem(.ol)
                formatItem(.checklist)
                formatItem(.quote)
                Divider()
                formatItem(.code)
                formatItem(.codeblock)
                formatItem(.hr)
                formatItem(.table)
                formatItem(.link, "k")
            }
            .disabled(notes == nil)
        }
        CommandGroup(replacing: .sidebar) {
            Button(sidebarVisible ? "Hide Sidebar" : "Show Sidebar") { sidebarVisible.toggle() }
                .keyboardShortcut("s", modifiers: [.command, .control])
                .disabled(!signedIn)
            Divider()
            Button("Toggle Details") { notes?.toggleDetails() }
                .keyboardShortcut("i", modifiers: [.command, .option])
                .disabled(notes == nil)
            Divider()
            Button("Previous Week or Month") { calendar?.previous() }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
                .disabled(calendar == nil)
            Button("Next Week or Month") { calendar?.next() }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
                .disabled(calendar == nil)
            Button("Today") { calendar?.today() }
                .keyboardShortcut("t", modifiers: [.command, .option])
                .disabled(calendar == nil)
            Button("Show Week") { calendar?.showWeek() }.disabled(calendar == nil)
            Button("Show Month") { calendar?.showMonth() }.disabled(calendar == nil)
            Divider()
            Button("Show 30 Days") { analytics?.setRange(.days30) }
                .keyboardShortcut("1", modifiers: [.command, .option])
                .disabled(analytics == nil)
            Button("Show 90 Days") { analytics?.setRange(.days90) }
                .keyboardShortcut("2", modifiers: [.command, .option])
                .disabled(analytics == nil)
            Button("Show All Time") { analytics?.setRange(.all) }
                .keyboardShortcut("3", modifiers: [.command, .option])
                .disabled(analytics == nil)
            Divider()
            Button("Refresh") { app.dataChanged() }
                .keyboardShortcut("r")
                .disabled(!signedIn)
        }
        CommandMenu("Go") {
            let order = SidebarGroups.order(enabled: enabled)
            Group {
                ForEach(Array(order.enumerated()), id: \.element) { i, key in
                    if i < 9 {
                        Button(ModuleMeta.of(key).label) { nav.selected = key }
                            .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")))
                    } else {
                        Button(ModuleMeta.of(key).label) { nav.selected = key }
                    }
                }
                Divider()
                // On the Notes screen ⌘K is Link in the Format menu
                Button("Search") { nav.searchOpen = true }
                    .keyboardShortcut(notes == nil ? KeyboardShortcut("k") : nil)
            }
            .disabled(!signedIn)
        }
        CommandGroup(replacing: .help) {
            Button("Obelo Help") { openWindow(id: "help") }
                .keyboardShortcut("?")
                .disabled(!signedIn)
            Button("Keyboard Shortcuts") { nav.shortcutsOpen = true }
                .disabled(!signedIn)
        }
        #if DEBUG
        CommandMenu("Debug") {
            Button("Kit Gallery") { openWindow(id: "kit-gallery") }
                .keyboardShortcut("g", modifiers: [.command, .option])
        }
        #endif
    }

    private func formatItem(_ format: MarkdownFormat, _ key: KeyEquivalent? = nil, _ modifiers: EventModifiers = .command) -> some View {
        Button(format.label) { notes?.format(format) }
            .keyboardShortcut(key.map { KeyboardShortcut($0, modifiers: modifiers) })
    }

    /// ⇧⌘N from anywhere: opens Notes, then asks it for a new note once it is on screen
    private func newNote() {
        let wasOnNotes = nav.selected == "notes"
        nav.selected = "notes"
        Task {
            if !wasOnNotes { try? await Task.sleep(for: .milliseconds(400)) }
            nav.newItem = Navigator.NewItemRequest(key: "notes")
        }
    }
}

/// The web's single-key shortcuts (src/views/layouts/main.ejs), active only when no text is being edited:
/// D Today, T Tasks, N new note, C Capture, A Analytics, B Bookmarks, H Help, / Search.
@MainActor
enum MacSingleKeys {
    private static let destinations: [String: String] = [
        "d": "dashboard", "t": "tasks", "c": "capture", "a": "analytics", "b": "bookmarks", 
    ]

    static func install(nav: Navigator, enabled: @escaping () -> [String]) -> Any? {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // The monitor runs on the main thread; the event stays inside this call
            nonisolated(unsafe) let e = event
            let used = MainActor.assumeIsolated { handle(e, nav: nav, enabled: enabled()) }
            return used ? nil : event
        }
    }

    static func remove(_ monitor: Any) { NSEvent.removeMonitor(monitor) }

    /// True when the key was used
    private static func handle(_ event: NSEvent, nav: Navigator, enabled: [String]) -> Bool {
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
              let window = event.window ?? NSApp.keyWindow,
              MacWindowConfigurator.isMain(window),
              window.attachedSheet == nil,
              !(window.firstResponder is NSText),
              let key = event.charactersIgnoringModifiers?.lowercased(), key.count == 1
        else { return false }
        if key == "n", enabled.contains("notes") {
            let wasOnNotes = nav.selected == "notes"
            nav.selected = "notes"
            Task {
                if !wasOnNotes { try? await Task.sleep(for: .milliseconds(400)) }
                nav.newItem = Navigator.NewItemRequest(key: "notes")
            }
            return true
        }
        if event.characters == "?" { nav.shortcutsOpen = true; return true }
        if key == "/" { nav.searchOpen = true; return true }
        if key == "h" { nav.helpRequest += 1; return true }
        guard let destination = destinations[key], enabled.contains(destination) else { return false }
        nav.selected = destination
        return true
    }
}
