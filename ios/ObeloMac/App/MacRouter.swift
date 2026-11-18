import SwiftUI

/// Opens things inside the app. The web page uses links; on the Mac a click on a row asks the router,
/// which switches module and leaves a request the screen picks up.
@MainActor @Observable
final class MacRouter {
    /// "Show this tab, select this task" for the Tasks screen
    struct TasksRequest: Equatable {
        let id = UUID()
        let view: String?
        let taskId: Int?
    }

    enum Destination {
        case module(String)
        case tasks(view: String?, task: Int?)
        case reminder(Int)
        case routine(Int)
        case note(Int)
        case list(Int)
        case event(CalendarEvent)
        case bookmark(Int)
    }

    var tasksRequest: TasksRequest?
    /// "Open this note" for the Notes screen
    var notesRequest: Int?
    /// "Show this reminder" for the Reminders screen
    var remindersRequest: Int?
    /// "Show this routine" for the Routines screen
    var routinesRequest: Int?
    /// "Show this list" for the Lists screen
    var listsRequest: Int?
    /// "Show this event" for the Calendar screen
    var calendarRequest: CalendarEvent?
    /// "Select this bookmark" for the Bookmarks screen
    var bookmarksRequest: Int?
    /// Set when a click in one module opened another ("from" Today "to" Tasks): Back goes to `from`
    struct Origin: Equatable { let from: String; let to: String }
    var origin: Origin?
    /// Text typed in Today's Quick Capture, for the Capture screen to pick up
    var captureText: String?

    private let nav: Navigator

    init(nav: Navigator) { self.nav = nav }

    func open(_ destination: Destination) {
        let from = nav.selected
        let to: String
        switch destination {
        case .module(let key): to = key
        case .tasks: to = "tasks"
        case .reminder: to = "reminders"
        case .routine: to = "routines"
        case .note: to = "notes"
        case .list: to = "lists"
        case .event: to = "calendar"
        case .bookmark: to = "bookmarks"
        }
        // Opening something from another screen remembers that screen, so Back returns to it
        if from != to { origin = Origin(from: from, to: to) }
        switch destination {
        case .module(let key): nav.selected = key
        case .tasks(let view, let task):
            tasksRequest = TasksRequest(view: view, taskId: task)
            nav.selected = "tasks"
        case .reminder(let id):
            remindersRequest = id
            nav.selected = "reminders"
        case .routine(let id):
            routinesRequest = id
            nav.selected = "routines"
        case .note(let id):
            notesRequest = id
            nav.selected = "notes"
        case .list(let id):
            listsRequest = id
            nav.selected = "lists"
        case .bookmark(let id):
            bookmarksRequest = id
            nav.selected = "bookmarks"
        case .event(let event):
            calendarRequest = event
            nav.selected = "calendar"
        }
    }

    /// Whether `module` has somewhere to go back to: the screen it was opened from
    func canGoBack(in module: String) -> Bool { origin?.to == module }

    /// Back: to the screen this module was opened from
    func goBack(in module: String) {
        guard let origin, origin.to == module else { return }
        self.origin = nil
        nav.selected = origin.from
    }
}
