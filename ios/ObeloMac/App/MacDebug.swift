#if DEBUG
import AppKit
import Foundation

/// Testing without a server. `-shellPreview YES` shows the signed-in shell with a made-up user and every
/// module switched on (the screens inside will have no data); `-windowSnapshot <file.png>` also writes the
/// main window's own drawing to a PNG and quits. Not a screen capture, so other windows don't matter.
enum MacDebug {
    /// `-signInPreview YES` shows the sign-in screen without contacting a server (with `-windowSnapshot`, draws it and quits)
    static func previewSignInIfAsked(_ app: AppState) async -> Bool {
        let d = UserDefaults.standard
        guard d.bool(forKey: "signInPreview") else { return false }
        app.phase = .signedOut
        app.theme = Theme.resolve(Appearance(theme: d.string(forKey: "galleryTheme") ?? "dark", isDark: true, customAccent: "#2563eb", customBase: "dark"))
        if d.string(forKey: "windowSnapshot") != nil {
            try? await Task.sleep(for: .seconds(2))
            await snapshotMainWindowAndQuit()
        }
        return true
    }

    private static func snapshotMainWindowAndQuit() async {
        let found = NSApp.windows.first(where: { MacWindowConfigurator.isMain($0) })
        print("snapshot: windows=\(NSApp.windows.count) found=\(found != nil) ids=\(NSApp.windows.map { $0.identifier?.rawValue ?? "nil" })")
        // A bare name (`-windowSnapshot lists.png`) goes in the app's own temporary folder, the one place the sandbox allows
        if var file = UserDefaults.standard.string(forKey: "windowSnapshot"),
           { if !file.hasPrefix("/") { file = NSTemporaryDirectory() + file; print("snapshot: writing \(file)") }; return true }(),
           let view = NSApp.windows.first(where: { MacWindowConfigurator.isMain($0) })?.contentView?.superview,
           let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: rep)
            do { try rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: file)) }
            catch { print("snapshot: could not write \(file): \(error.localizedDescription)") }
        } else {
            print("snapshot: no window drawing to write")
        }
        NSApp.terminate(nil)
    }

    static func previewShellIfAsked(_ app: AppState) async -> Bool {
        let d = UserDefaults.standard
        guard d.bool(forKey: "shellPreview") else { return false }
        let keys = ["dashboard", "capture", "tasks", "reminders", "routines", "notes", "lists", "bookmarks", "calendar", "analytics", "ai"]
        let modules = keys.map { ["key": $0, "label": $0.capitalized, "beta": false] as [String: Any] }
        let json: [String: Any] = [
            "user": ["id": 1, "username": "sample", "displayName": "Sample Person", "email": "sample@example.com", "role": "user", "timezone": "UTC"],
            "appearance": ["theme": d.string(forKey: "galleryTheme") ?? "dark", "isDark": true, "customAccent": "#2563eb", "customBase": "dark"],
            "hour12": true, "modules": modules, "mobileNav": ["dashboard"], "aiEnabled": !d.bool(forKey: "aiOff"), "canLockNotes": true, "version": "3.49.0", "notePaper": d.string(forKey: "notePaper") ?? "theme",
        ]
        do {
            let data = try JSONSerialization.data(withJSONObject: json)
            _ = try JSONDecoder().decode(Me.self, from: data)
        } catch { print("shellPreview: could not build the sample user: \(error)"); return false }
        guard let data = try? JSONSerialization.data(withJSONObject: json), let me = try? JSONDecoder().decode(Me.self, from: data) else { return false }
        app.me = me
        app.theme = Theme.resolve(me.appearance)
        app.phase = .signedIn
        // Testing: `-windowWidth 900` sets the window's content width before drawing
        let width = d.double(forKey: "windowWidth")
        if width > 0 {
            try? await Task.sleep(for: .milliseconds(300))
            NSApp.windows.first(where: { MacWindowConfigurator.isMain($0) })?.setContentSize(NSSize(width: width, height: 840))
        }
        if d.string(forKey: "windowSnapshot") != nil {
            NotificationCenter.default.addObserver(forName: APIClient.unauthorizedNotification, object: nil, queue: .main) { _ in
                print("shellPreview: a request was refused (401), so the app signed out")
            }
            try? await Task.sleep(for: .seconds(3))
            print("shellPreview: phase at snapshot = \(app.phase)")
            await snapshotMainWindowAndQuit()
        }
        return true
    }
}

// MARK: Sample tasks

/// A stand-in server for the Tasks screen when `-shellPreview YES` is on: a few tasks in memory, so the
/// screen can be drawn and driven without a server. Complete, delete, save and subtasks change the list.
@MainActor
final class PreviewTasksAPI: TasksAPI {
    private var tasks: [TaskItem]
    private var nextId = 100

    init() {
        let cal = Calendar.current
        func ymd(_ days: Int) -> String { Fmt.ymd(cal.date(byAdding: .day, value: days, to: Date())!) }
        func make(_ id: Int, _ title: String, status: String = "inbox", priority: String = "none", due: Int? = nil,
                  time: String? = nil, tags: [String] = [], notes: String = "", recur: String? = nil,
                  subs: [(Int, String, Bool)] = []) -> TaskItem {
            let state: Any = due.flatMap { (d: Int) -> String? in d < 0 ? "overdue" : d == 0 ? "today" : nil } ?? NSNull()
            let obj: [String: Any] = [
                "id": id, "title": title, "notes": notes, "status": status, "priority": priority,
                "dueDate": due.map { ymd($0) } ?? NSNull(), "dueTime": time ?? NSNull(), "tags": tags,
                "recurring": recur != nil, "recurRule": recur ?? NSNull(),
                "createdAt": "2026-11-10T10:00:00.000Z", "updatedAt": "2026-11-14T10:00:00.000Z", "dueState": state,
                "subtasks": subs.map { ["id": $0.0, "title": $0.1, "done": $0.2] as [String: Any] },
            ]
            let d = JSONDecoder()
            d.dateDecodingStrategy = .custom { dec in
                try Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(try dec.singleValueContainer().decode(String.self))
            }
            return try! d.decode(TaskItem.self, from: JSONSerialization.data(withJSONObject: obj))
        }
        tasks = [
            make(1, "Send the quarterly report", status: "in-progress", priority: "high", due: -2, tags: ["work"],
                 notes: "## Before sending\nInclude the **churn numbers** and the new forecast.\n\n- [x] Pull the numbers\n- [ ] Check with _Dana_ first\n- Add the `Q4` chart\n\n> Keep it to one page.\n\n1. Draft\n2. Review",
                 subs: [(1, "Pull the numbers", true), (2, "Write the summary", false), (3, "Get sign-off", false)]),
            make(2, "Book the dentist", status: "today", priority: "medium", due: 0, time: "15:00", tags: ["health"]),
            make(3, "Order a new desk lamp", priority: "low", due: 5, tags: ["home", "errands"]),
            make(4, "Read the standards draft"),
            make(5, "Water the plants", status: "today", priority: "low", due: 1, tags: ["home"], recur: "weekly"),
            make(6, "Plan the offsite", priority: "high", due: 12, tags: ["work"]),
            make(7, "Renew the library card", status: "done"),
        ]
    }

    private func visible(_ view: String) -> [TaskItem] {
        switch view {
        case "inbox": tasks.filter { $0.status == "inbox" }
        case "today": tasks.filter { $0.status == "today" }
        case "upcoming": tasks.filter { $0.dueDate != nil && !$0.isDone }
        case "completed": tasks.filter { $0.isDone }
        case "archived": tasks.filter { $0.status == "archived" }
        case "slipping": []
        default: tasks
        }
    }

    func list(view: String, tag: String?, search: String?) async throws -> TasksListResponse {
        var rows = visible(view)
        if let tag { rows = rows.filter { $0.tags.contains(tag) } }
        if let search, !search.isEmpty { rows = rows.filter { $0.title.localizedCaseInsensitiveContains(search) } }
        return TasksListResponse(tasks: rows, tags: ["work", "home", "health", "errands"],
                                 counts: .init(today: visible("today").count, inbox: visible("inbox").count, slipping: 0))
    }
    func detail(id: Int) async throws -> TaskItem { tasks.first { $0.id == id }! }
    func create(_ body: [String: Any]) async throws -> TaskItem {
        nextId += 1
        let t = try Self.decode(["id": nextId, "title": body["title"] as? String ?? "", "status": body["status"] as? String ?? "inbox"])
        tasks.insert(t, at: 0)
        return t
    }
    func update(id: Int, _ body: [String: Any]) async throws -> TaskItem {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return tasks[0] }
        var t = tasks[i]
        t.title = body["title"] as? String ?? t.title
        t.notes = body["notes"] as? String ?? t.notes
        t.status = body["status"] as? String ?? t.status
        t.priority = body["priority"] as? String ?? t.priority
        t.dueDate = body["dueDate"] as? String
        t.dueTime = body["dueTime"] as? String
        t.tags = body["tags"] as? [String] ?? t.tags
        t.recurring = body["recurring"] as? Bool ?? t.recurring
        t.recurRule = body["recurRule"] as? String
        tasks[i] = t
        return t
    }
    func complete(id: Int) async throws { setStatus(id, "done") }
    func restore(id: Int) async throws { setStatus(id, "inbox") }
    func delete(id: Int) async throws { tasks.removeAll { $0.id == id } }
    func bulk(action: String, ids: [Int]) async throws {
        for id in ids {
            switch action {
            case "complete": setStatus(id, "done")
            case "archive": setStatus(id, "archived")
            case "restore": setStatus(id, "inbox")
            default: if let i = tasks.firstIndex(where: { $0.id == id }) { tasks[i].priority = action }
            }
        }
    }
    func addSubtask(taskId: Int, title: String) async throws { try await editSubtasks(taskId) { $0.append(.init(id: Int.random(in: 1000...9999), title: title, done: false)) } }
    func toggleSubtask(taskId: Int, subtaskId: Int) async throws {
        try await editSubtasks(taskId) { subs in subs = subs.map { $0.id == subtaskId ? .init(id: $0.id, title: $0.title, done: !$0.done) : $0 } }
    }
    func deleteSubtask(taskId: Int, subtaskId: Int) async throws { try await editSubtasks(taskId) { $0.removeAll { $0.id == subtaskId } } }
    func allTags() async throws -> [String] { ["work", "home", "health", "errands", "reading"] }

    private func setStatus(_ id: Int, _ status: String) {
        if let i = tasks.firstIndex(where: { $0.id == id }) { tasks[i].status = status }
    }
    private func editSubtasks(_ id: Int, _ change: (inout [TaskItem.Subtask]) -> Void) async throws {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        var subs = tasks[i].subtasks ?? []
        change(&subs)
        tasks[i].subtasks = subs
    }
    private static func decode(_ partial: [String: Any]) throws -> TaskItem {
        var obj: [String: Any] = ["notes": "", "status": "inbox", "priority": "none", "tags": [String](), "recurring": false,
                                  "createdAt": "2026-11-15T10:00:00.000Z", "updatedAt": "2026-11-15T10:00:00.000Z"]
        obj.merge(partial) { $1 }
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { dec in
            try Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(try dec.singleValueContainer().decode(String.self))
        }
        return try d.decode(TaskItem.self, from: JSONSerialization.data(withJSONObject: obj))
    }
}

extension TasksScreenModel {
    /// The screen's model: against the sample server when `-shellPreview YES` is on, otherwise the real one
    static func make() -> TasksScreenModel {
        UserDefaults.standard.bool(forKey: "shellPreview") ? TasksScreenModel(store: TasksStore(api: PreviewTasksAPI())) : TasksScreenModel()
    }
}

// MARK: Sample reminders

/// A stand-in server for the Reminders screen when `-shellPreview YES` is on: a few reminders in memory.
/// `-remindersView overdue|today|completed` picks the tab, `-remindersSelect 1,2` selects rows,
/// `-remindersNew YES` opens the new form.
@MainActor
final class PreviewRemindersAPI: RemindersAPI {
    private var reminders: [ReminderItem] = []
    private var nextId = 100

    init() {
        let cal = Calendar.current
        func ymd(_ days: Int) -> String { Fmt.ymd(cal.date(byAdding: .day, value: days, to: Date())!) }
        func make(_ id: Int, _ title: String, due: Int, time: String, state: String? = nil, priority: String = "none", tags: [String] = [],
                  recur: String? = nil, done: Bool = false, notes: String = "", offset: Int = 0) -> ReminderItem {
            var obj: [String: Any] = ["id": id, "title": title, "notes": notes, "dueDate": ymd(due), "dueTime": time, "priority": priority,
                                      "tags": tags, "completed": done, "recurring": recur != nil, "recurLabel": Fmt.recurLabel(recur),
                                      "createdAt": "2026-11-10T10:00:00.000Z", "reminderOffset": offset,
                                      "reminderAt": "2026-11-20T08:45:00.000Z"]
            if let recur { obj["recurRule"] = recur }
            if let state { obj["dueState"] = state }
            if done { obj["completedAt"] = "2026-11-14T16:00:00.000Z" }
            return try! Self.decoder.decode(ReminderItem.self, from: JSONSerialization.data(withJSONObject: obj))
        }
        reminders = [
            make(1, "Send the invoice to Dana", due: -2, time: "09:00", state: "overdue", priority: "high", tags: ["work"],
                 notes: "Attach the signed PDF and copy accounts.", offset: 15),
            make(2, "Call the dentist", due: -1, time: "16:30", state: "overdue", priority: "medium", tags: ["health"]),
            make(3, "Stand-up notes", due: 0, time: "10:00", state: "today", tags: ["work"], recur: "weekdays"),
            make(4, "Pick up the parcel", due: 0, time: "17:30", state: "today", priority: "low", tags: ["errands"]),
            make(5, "Renew the car insurance", due: 6, time: "09:00", priority: "high", tags: ["home"], offset: 60),
            make(6, "Water the plants", due: 2, time: "08:00", tags: ["home"], recur: "weekly"),
            make(7, "Book flights for the offsite", due: 14, time: "12:00", tags: ["work", "travel"]),
            make(8, "Return the library books", due: -3, time: "11:00", done: true),
            make(9, "Send the quarterly report", due: -5, time: "15:00", tags: ["work"], done: true),
        ]
    }

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { dec in
            try Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(try dec.singleValueContainer().decode(String.self))
        }
        return d
    }()

    private func visible(_ view: String) -> [ReminderItem] {
        switch view {
        case "today": reminders.filter { !$0.completed && $0.dueState == "today" }
        case "overdue": reminders.filter { !$0.completed && $0.dueState == "overdue" }
        case "completed": reminders.filter { $0.completed }
        default: reminders.filter { !$0.completed && $0.dueState != "overdue" }
        }
    }

    func list(view: String, tag: String?) async throws -> RemindersListResponse {
        var rows = visible(view)
        if let tag { rows = rows.filter { $0.tags.contains(tag) } }
        return RemindersListResponse(reminders: rows, tags: ["errands", "health", "home", "travel", "work"],
                                     counts: .init(overdue: visible("overdue").count, today: visible("today").count))
    }
    func detail(id: Int) async throws -> ReminderItem { reminders.first { $0.id == id } ?? reminders[0] }
    func create(_ body: [String: Any]) async throws -> ReminderItem {
        nextId += 1
        let obj: [String: Any] = ["id": nextId, "title": body["title"] as? String ?? "", "notes": "", "dueDate": body["dueDate"] as? String ?? "",
                                  "dueTime": body["dueTime"] as? String ?? "", "priority": "none", "tags": [String](), "completed": false,
                                  "recurring": false, "recurLabel": "", "createdAt": "2026-11-15T10:00:00.000Z"]
        let r = try Self.decoder.decode(ReminderItem.self, from: JSONSerialization.data(withJSONObject: obj))
        reminders.append(r)
        return r
    }
    func update(id: Int, _ body: [String: Any]) async throws -> ReminderItem {
        guard let i = reminders.firstIndex(where: { $0.id == id }) else { return reminders[0] }
        reminders[i].title = body["title"] as? String ?? reminders[i].title
        reminders[i].notes = body["notes"] as? String ?? reminders[i].notes
        reminders[i].priority = body["priority"] as? String ?? reminders[i].priority
        reminders[i].tags = body["tags"] as? [String] ?? reminders[i].tags
        return reminders[i]
    }
    func complete(id: Int) async throws { reminders.removeAll { $0.id == id } }
    func restore(id: Int) async throws {}
    func delete(id: Int) async throws { reminders.removeAll { $0.id == id } }
    func snooze(id: Int, duration: String) async throws {}
    func bulk(action: String, ids: [Int]) async throws -> Int {
        let n = reminders.filter { ids.contains($0.id) }.count
        reminders.removeAll { ids.contains($0.id) }
        return n
    }
    func allTags() async throws -> [String] { ["errands", "health", "home", "travel", "work", "reading"] }
}

extension RemindersScreenModel {
    /// The screen's model: against the sample server when `-shellPreview YES` is on, otherwise the real one
    static func make() -> RemindersScreenModel {
        UserDefaults.standard.bool(forKey: "shellPreview") ? RemindersScreenModel(store: RemindersStore(api: PreviewRemindersAPI())) : RemindersScreenModel()
    }
}

// MARK: Sample routines

/// A stand-in server for the Routines screen when `-shellPreview YES` is on: a few routines in memory.
/// `-routinesView all|archived` picks the tab, `-routinesSelect 1,2` selects rows (ids 1 to 8),
/// `-routinesNew YES` opens the new form.
@MainActor
final class PreviewRoutinesAPI: RoutinesAPI {
    private var routines: [Routine] = []
    private var nextId = 100

    init() {
        func make(_ id: Int, _ title: String, tod: String, freq: String = "daily", days: [String] = [], due: Bool = true, done: Bool = false,
                  streak: Int = 0, best: Int? = nil, count: Int = 0, duration: Int? = nil, active: Bool = true, finished: Bool? = nil,
                  tags: [String] = [], time: String? = nil, notify: Bool = false, desc: String = "") -> Routine {
            var obj: [String: Any] = ["id": id, "title": title, "description": desc, "timeOfDay": tod, "frequency": freq, "scheduleDays": days,
                                      "streakCurrent": streak, "streakBest": best ?? streak, "tags": tags, "notify": notify, "active": active,
                                      "completionCount": count, "completedToday": done, "dueToday": due, "createdAt": "2026-09-14T10:00:00.000Z"]
            if let duration { obj["durationDays"] = duration; obj["startDate"] = "2026-10-20" }
            if let finished { obj["finishedChallenge"] = finished }
            if let time { obj["specificTime"] = time }
            let d = JSONDecoder()
            d.dateDecodingStrategy = .custom { dec in
                try Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(try dec.singleValueContainer().decode(String.self))
            }
            return try! d.decode(Routine.self, from: JSONSerialization.data(withJSONObject: obj))
        }
        routines = [
            make(1, "Morning walk", tod: "morning", done: true, streak: 12, best: 21, count: 64, tags: ["health"], time: "07:30", notify: true, desc: "Around the block, no phone."),
            make(2, "Read 20 pages", tod: "evening", streak: 5, best: 9, count: 12, duration: 30, tags: ["reading"]),
            make(3, "Stretch", tod: "morning", count: 8, tags: ["health"]),
            make(4, "Take vitamins", tod: "morning", done: true, streak: 3, best: 40, count: 90),
            make(5, "Water the plants", tod: "afternoon", freq: "weekly", days: ["Sat"], due: true, count: 14, tags: ["home"]),
            make(6, "Weekly review", tod: "anytime", freq: "weekly", days: ["Fri"], due: false, streak: 6, best: 8, count: 22),
            make(7, "30 days of reading", tod: "evening", streak: 0, best: 21, count: 30, duration: 30, active: false, finished: true, tags: ["reading"]),
            make(8, "Cold showers", tod: "morning", count: 4, duration: 14, active: false, finished: false),
        ]
    }

    func list(view: String, tag: String?) async throws -> RoutinesListResponse {
        var rows = routines.filter { $0.active == (view != "archived") }
        if let tag { rows = rows.filter { $0.tags.contains(tag) } }
        return RoutinesListResponse(routines: rows, tags: ["health", "home", "reading"])
    }

    func detail(id: Int) async throws -> RoutineDetail {
        let r = routines.first { $0.id == id } ?? routines[0]
        let cal = Calendar.current
        let weeks: [[HeatmapDay]] = (0..<12).map { w in
            (0..<7).map { d in
                let n = w * 7 + d
                let future = w == 11 && d > 3
                let date = cal.date(byAdding: .day, value: n - 11 * 7 - 4, to: Date())!
                return HeatmapDay(dateStr: Fmt.ymd(date), isFuture: future, notApplicable: d == 6 && r.frequency == "weekdays",
                                  completed: !future && (n % 5 != 0 && n % 7 != 3), label: Fmt.shortDay(Fmt.ymd(date)))
            }
        }
        let stats: [WeeklyStat] = (0..<12).map { i in
            let rate = [86, 100, 71, 57, 43, 14, 0, 86, 100, 86, 71, 57][i]
            return WeeklyStat(label: Fmt.shortDay(Fmt.ymd(cal.date(byAdding: .day, value: (i - 11) * 7, to: Date())!)),
                              completionCount: rate * 7 / 100, dayCount: 7, rate: rate)
        }
        return RoutineDetail(routine: r, heatmap: weeks, weeklyStats: stats)
    }

    func create(_ body: [String: Any]) async throws -> Routine {
        nextId += 1
        let obj: [String: Any] = ["id": nextId, "title": body["title"] as? String ?? "", "description": "", "timeOfDay": body["timeOfDay"] as? String ?? "anytime",
                                  "frequency": "daily", "scheduleDays": [String](), "streakCurrent": 0, "streakBest": 0, "tags": [String](),
                                  "notify": false, "active": true, "completionCount": 0, "completedToday": false, "dueToday": true]
        let r = try JSONDecoder().decode(Routine.self, from: JSONSerialization.data(withJSONObject: obj))
        routines.append(r)
        return r
    }
    func update(id: Int, _ body: [String: Any]) async throws -> Routine {
        guard let i = routines.firstIndex(where: { $0.id == id }) else { return routines[0] }
        routines[i].title = body["title"] as? String ?? routines[i].title
        routines[i].description = body["description"] as? String ?? routines[i].description
        routines[i].tags = body["tags"] as? [String] ?? routines[i].tags
        return routines[i]
    }
    func complete(id: Int) async throws -> Routine {
        guard let i = routines.firstIndex(where: { $0.id == id }) else { return routines[0] }
        routines[i].completedToday.toggle()
        return routines[i]
    }
    func archive(id: Int) async throws {}
    func delete(id: Int) async throws { routines.removeAll { $0.id == id } }
    func bulk(action: String, ids: [Int]) async throws -> Int {
        let n = routines.filter { ids.contains($0.id) }.count
        if action == "delete" { routines.removeAll { ids.contains($0.id) } }
        return n
    }
    func allTags() async throws -> [String] { ["health", "home", "reading", "mindfulness"] }
}

extension RoutinesScreenModel {
    /// The screen's model: against the sample server when `-shellPreview YES` is on, otherwise the real one
    static func make() -> RoutinesScreenModel {
        UserDefaults.standard.bool(forKey: "shellPreview") ? RoutinesScreenModel(store: RoutinesStore(api: PreviewRoutinesAPI())) : RoutinesScreenModel()
    }
}

// MARK: Sample Today page

/// A stand-in server for the Today screen when `-shellPreview YES` is on: a made-up dashboard, so the
/// page can be drawn without a server. `-todayState empty` shows a day with nothing in it; `-todayCards`
/// (comma-separated keys) picks and orders the cards, like Settings ▸ Dashboard.
@MainActor
final class PreviewTodayAPI: TodayAPI {
    private var dashboard: Dashboard

    init() {
        let d = UserDefaults.standard
        let empty = d.string(forKey: "todayState") == "empty"
        let cal = Calendar.current
        func ymd(_ days: Int) -> String { Fmt.ymd(cal.date(byAdding: .day, value: days, to: Date())!) }
        func task(_ id: Int, _ title: String, priority: String = "none", due: Int? = nil, time: String? = nil, state: String? = nil) -> [String: Any] {
            ["id": id, "title": title, "notes": "", "status": "today", "priority": priority, "dueDate": due.map { ymd($0) } ?? NSNull(),
             "dueTime": time ?? NSNull(), "tags": [String](), "recurring": false,
             "createdAt": "2026-11-10T10:00:00.000Z", "updatedAt": "2026-11-14T10:00:00.000Z", "dueState": state ?? NSNull()]
        }
        func reminder(_ id: Int, _ title: String, due: Int, time: String, state: String?) -> [String: Any] {
            ["id": id, "title": title, "notes": "", "dueDate": ymd(due), "dueTime": time, "priority": "none", "tags": [String](),
             "completed": false, "recurring": false, "recurLabel": "", "createdAt": "2026-11-10T10:00:00.000Z", "dueState": state ?? NSNull()]
        }
        func routine(_ id: Int, _ title: String, _ tod: String, streak: Int = 0, done: Bool = false, days: Int? = nil, freq: String = "daily") -> [String: Any] {
            var r: [String: Any] = ["id": id, "title": title, "description": "", "timeOfDay": tod, "frequency": freq, "scheduleDays": [String](),
                                    "streakCurrent": streak, "streakBest": streak, "tags": [String](), "notify": false, "active": true,
                                    "completionCount": 4, "completedToday": done, "dueToday": true]
            if let days { r["durationDays"] = days }
            return r
        }
        func event(_ id: Int, _ title: String, hour: Int, allDay: Bool = false, color: String) -> [String: Any] {
            let day = ymd(0)
            return ["id": id, "title": title, "startAt": "\(day)T\(String(format: "%02d", hour)):00:00.000Z", "endAt": "\(day)T\(String(format: "%02d", hour + 1)):00:00.000Z",
                    "allDay": allDay, "calendarName": "Personal", "color": color, "day": day, "editable": true, "deletable": true]
        }
        let all = ["focus", "calendar", "due_items", "routines", "resurfaced", "review"]
        let chosen = d.string(forKey: "todayCards").map { $0.split(separator: ",").map(String.init) } ?? all
        let widgets = chosen.map { ["key": $0, "enabled": true] as [String: Any] } + all.filter { !chosen.contains($0) }.map { ["key": $0, "enabled": false] }
        let json: [String: Any] = empty ? [
            "widgets": widgets, "slippingCount": 0, "focusTasks": [], "events": [], "due": [], "routines": [], "resurfaced": NSNull(), "review": [], "stale": [],
        ] : [
            "widgets": widgets, "slippingCount": 2,
            "focusTasks": [task(1, "Send the quarterly report", priority: "high", due: 0, time: "17:00", state: "today"), task(2, "Book the dentist", priority: "medium")],
            "events": [event(1, "Team standup", hour: 9, color: "#6366f1"), event(2, "Lunch with Sam", hour: 12, color: "#22c55e"), event(3, "Dentist's birthday", hour: 0, allDay: true, color: "#f59e0b")],
            "due": [
                ["type": "task", "overdue": true, "task": task(3, "Pay the electricity bill", priority: "high", due: -2, state: "overdue")],
                ["type": "reminder", "overdue": false, "reminder": reminder(7, "Call the plumber", due: 0, time: "15:30", state: "today")],
                ["type": "task", "overdue": false, "task": task(4, "Renew the library card", due: 0, state: "today")],
            ],
            "routines": [routine(10, "Stretch for ten minutes", "morning", streak: 6, done: true), routine(11, "Read for 20 minutes", "evening", streak: 3, days: 30),
                         routine(12, "Water the plants", "anytime", freq: "weekly")],
            "resurfaced": ["id": 5, "title": "Ideas for the offsite", "type": "journal", "createdAt": "2026-08-12T10:00:00.000Z",
                           "preview": "A few things I want to try this year: a shorter agenda, a walk after lunch, and one decision per session so nobody leaves with a list of maybes."],
            "review": [["id": 50, "title": "Standards draft, second pass", "reviewDate": ymd(-1)]],
            "stale": [["id": 51, "title": "Notes from the March call", "daysAgo": 36]],
        ]
        let data = try! JSONSerialization.data(withJSONObject: json)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { dec in
            try Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(try dec.singleValueContainer().decode(String.self))
        }
        dashboard = try! decoder.decode(Dashboard.self, from: data)
    }

    func dashboard() async throws -> Dashboard { dashboard }
    func completeTask(id: Int) async throws {}
    func completeReminder(id: Int) async throws {}
    func snoozeReminder(id: Int, duration: String) async throws {}
    func toggleRoutine(id: Int) async throws -> Routine {
        var r = dashboard.routines.first { $0.id == id }!
        r.completedToday.toggle()
        return r
    }
    func markReviewed(noteId: Int) async throws {}
}

extension MacDebug {
    /// The Today screen's store: against the sample page when `-shellPreview YES` is on, otherwise the real one
    static func todayStore() -> TodayStore {
        UserDefaults.standard.bool(forKey: "shellPreview") ? TodayStore(api: PreviewTodayAPI()) : TodayStore()
    }
}

// MARK: Sample Capture

/// A stand-in server for the Capture screen when `-shellPreview YES` is on. `-captureState` picks what
/// shows: `typed`, `error`, or a type (`task`, `reminder`, `note`, `journal`, `quote`, `list`, `bookmark`)
/// to show that kind of suggestion. `-aiOff YES` shows the page for a server with no AI.
@MainActor
final class PreviewCaptureAPI: CaptureAPI {
    func process(raw: String, type: String?) async throws -> CaptureDraft { CaptureDraft(draftId: 1, suggestion: PreviewCaptureAPI.suggestion(type ?? "task")) }
    func confirm(draftId: Int, body: [String: Any]) async throws -> CaptureSaved { CaptureSaved(type: body["type"] as? String ?? "note", id: 1) }
    func reject(draftId: Int) async throws {}
    func allTags() async throws -> [String] { ["work", "home", "health", "travel", "reading"] }

    static func suggestion(_ type: String) -> CaptureSuggestion {
        var obj: [String: Any] = ["type": type, "tags": ["health", "home"], "confidence": "high"]
        switch type {
        case "task": obj.merge(["title": "Finish the slides", "content": "For the Friday review.", "dueDate": Fmt.ymd(Date().addingTimeInterval(86400 * 3)), "priority": "high", "confidence": "medium"]) { $1 }
        case "reminder": obj.merge(["title": "Call the dentist", "dueDate": Fmt.ymd(Date().addingTimeInterval(86400 * 2)), "dueTime": "15:00", "priority": "medium"]) { $1 }
        case "note", "journal": obj.merge(["title": "Ideas for the weekend trip", "content": "Somewhere with a train line.\nBring the good camera.", "source": "Conversation", "confidence": "low"]) { $1 }
        case "quote": obj.merge(["title": "Four Thousand Weeks", "content": "Time management for mortals.", "source": "Book", "author": "Oliver Burkeman"]) { $1 }
        case "list": obj.merge(["title": "Groceries", "items": ["Milk", "Eggs", "Bread", "Pasta"]]) { $1 }
        case "bookmark": obj.merge(["title": "React docs", "url": "https://react.dev", "content": "The official documentation."]) { $1 }
        default: break
        }
        return try! JSONDecoder().decode(CaptureSuggestion.self, from: JSONSerialization.data(withJSONObject: obj))
    }
}

extension MacDebug {
    /// The Capture screen's store: against the sample server when `-shellPreview YES` is on, otherwise the real one
    static func captureStore() -> CaptureStore {
        let d = UserDefaults.standard
        guard d.bool(forKey: "shellPreview") else { return CaptureStore() }
        let store = CaptureStore(api: PreviewCaptureAPI())
        switch d.string(forKey: "captureState") {
        case "typed": store.raw = "take out the trash at 10am"
        case "typedTask": store.raw = "take out the trash at 10am"; store.chosenType = "task"
        case "error": store.raw = "buy milk"; store.error = "Couldn't reach the AI service. Try again in a moment."
        case let type? where CaptureTypes.all.contains(type):
            store.raw = "remind me to call the dentist tuesday 3pm"
            store.adopt(CaptureDraft(draftId: 1, suggestion: PreviewCaptureAPI.suggestion(type)))
        default: break
        }
        return store
    }
}

// MARK: Sample Notes

/// A stand-in server for the Notes screen when `-shellPreview YES` is on: folders, notes and one open note
/// in memory. `-notesOpen 3` opens a note, `-notesPreview YES` shows it in Preview, and `-notesDetailsVisible NO` hides Details.
@MainActor
final class PreviewNotesAPI: NotesAPI {
    var notes: [NoteSummary]
    var folders: [NoteFolder]

    init() {
        func note(_ id: Int, _ title: String, folder: Int? = nil, pinned: Bool = false, locked: Bool = false) -> NoteSummary {
            Self.summary(id, title, folder: folder, pinned: pinned, locked: locked)
        }
        notes = [note(1, "Reading list"), note(2, "Budget 2027", folder: 10), note(3, "Quarterly goals", folder: 11, pinned: true),
                 note(4, "Chores", folder: 12), note(5, "Salary notes", folder: 10, locked: true), note(6, "Weekend trip ideas", folder: 12, pinned: true)]
        folders = [Self.folder(10, "Work"), Self.folder(11, "Plans", parent: 10), Self.folder(12, "Home")]
    }

    func list(search: String?) async throws -> [NoteSummary] {
        guard let search, !search.isEmpty else { return notes }
        return notes.filter { $0.title.localizedCaseInsensitiveContains(search) }
    }
    func folders() async throws -> [NoteFolder] { folders }
    func createNote(_ body: [String: Any]) async throws -> Int { 99 }
    func createFolder(name: String, parentId: Int?) async throws {}
    func renameFolder(id: Int, name: String) async throws {}
    func deleteFolder(id: Int) async throws {}
    func move(note: Int, to folder: Int?) async throws {}
    func togglePin(id: Int) async throws {}
    func deleteNote(id: Int) async throws {}

    static func summary(_ id: Int, _ title: String, folder: Int?, pinned: Bool, locked: Bool) -> NoteSummary {
        var obj: [String: Any] = [
            "id": id, "type": "note", "title": title, "preview": "", "tags": [String](), "pinned": pinned, "flaggedForReview": false,
            "locked": locked, "hasDrawing": false, "private": false,
            "createdAt": "2026-10-02T10:00:00.000Z", "updatedAt": "2026-11-14T10:00:00.000Z",
        ]
        if let folder { obj["folderId"] = folder }
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { dec in
            try Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(try dec.singleValueContainer().decode(String.self))
        }
        return try! d.decode(NoteSummary.self, from: JSONSerialization.data(withJSONObject: obj))
    }

    static func folder(_ id: Int, _ name: String, parent: Int? = nil) -> NoteFolder {
        var obj: [String: Any] = ["id": id, "name": name]
        if let parent { obj["parentId"] = parent }
        return try! JSONDecoder().decode(NoteFolder.self, from: JSONSerialization.data(withJSONObject: obj))
    }

    /// The open note's full fields
    static func openNote(_ id: Int) -> Note {
        var obj: [String: Any] = [
            "id": id, "type": id == 6 ? "journal" : "note", "title": id == 3 ? "Quarterly goals" : "Weekend trip ideas",
            "preview": "", "tags": ["work", "planning"], "pinned": true, "flaggedForReview": id == 6, "locked": false, "hasDrawing": false,
            "private": false, "folderId": id == 3 ? 11 : 12, "createdAt": "2026-10-02T10:00:00.000Z", "updatedAt": "2026-11-14T10:00:00.000Z",
            "content": "## Goals for Q1\n\nThree things matter this quarter:\n\n- Ship the **Mac app** to TestFlight\n- Finish the *Notes* rebuild\n- [x] Write the release notes\n- [ ] Ask Dana about the budget\n\n> Keep the list short.\n\n1. Plan\n2. Build\n3. Review\n\nSee `docs/MAC-APP-PLAN.md` for the plan.",
            "attachments": [], "thoughts": [],
        ]
        switch id {
        case 3:   // attachments and thoughts
            obj["attachments"] = [
                ["id": 1, "mimeType": "image/png", "url": "/notes/3/attachments/1-whiteboard.png"],
                ["id": 2, "mimeType": "image/jpeg", "url": "/notes/3/attachments/2-site-photo.jpg"],
                ["id": 3, "mimeType": "application/pdf", "url": "/notes/3/attachments/3-budget-2027.pdf"],
                ["id": 4, "mimeType": "text/plain", "url": "/notes/3/attachments/4-meeting-minutes.txt"],
            ]
            obj["thoughts"] = [
                ["id": 1, "content": "Check the numbers with Dana before Friday.", "createdAt": "2026-11-12T10:00:00.000Z", "author": "Eric"],
                ["id": 2, "content": "The second goal slips if the Mac release does.", "createdAt": "2026-11-14T09:00:00.000Z", "author": "Eric"],
            ]
        case 5:   // locked
            obj["locked"] = true
            obj["title"] = "Salary notes"
            obj["content"] = NSNull()
        case 7:   // handwritten
            obj["title"] = "Sketch"
            obj["hasDrawing"] = true
            obj["content"] = ""
            obj["drawingData"] = sampleDrawingJSON
        default: break
        }
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { dec in
            try Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(try dec.singleValueContainer().decode(String.self))
        }
        return try! d.decode(Note.self, from: JSONSerialization.data(withJSONObject: obj))
    }

    /// A handwritten sample in the four pen colours, made at 600 wide
    static var sampleDrawingJSON: String {
        func stroke(_ color: String, _ width: Double, _ pts: [(Double, Double)]) -> [String: Any] {
            ["color": color, "width": width, "eraser": false, "points": pts.map { ["x": $0.0, "y": $0.1, "p": 0.5] }]
        }
        let wave = { (y: Double) in (0..<12).map { i in (40 + Double(i) * 40, y + sin(Double(i) / 1.5) * 22) } }
        let doc: [String: Any] = ["v": 1, "w": 600, "h": 1200, "strokes": [
            stroke("#f1f5f9", 3, wave(80)), stroke("#93c5fd", 3, wave(150)), stroke("#fca5a5", 6, wave(220)), stroke("#86efac", 3, wave(290)),
        ]]
        return String(data: try! JSONSerialization.data(withJSONObject: doc), encoding: .utf8)!
    }

    /// Stand-in pictures for the sample attachments (the real ones come from the server)
    static func preloadSampleImages() {
        for (path, hue) in [("/notes/3/attachments/1-whiteboard.png", 0.58), ("/notes/3/attachments/2-site-photo.jpg", 0.08)] {
            let image = NSImage(size: NSSize(width: 128, height: 128), flipped: false) { rect in
                NSGradient(starting: NSColor(hue: hue, saturation: 0.5, brightness: 0.9, alpha: 1),
                           ending: NSColor(hue: hue + 0.1, saturation: 0.7, brightness: 0.45, alpha: 1))?.draw(in: rect, angle: 60)
                return true
            }
            KitImageLoader.shared.preload(path: path, image: image)
        }
    }
}

extension MacDebug {
    /// The Notes screen's model: against the sample data when `-shellPreview YES` is on, otherwise the real one
    static func notesModel() -> NotesScreenModel {
        guard UserDefaults.standard.bool(forKey: "shellPreview") else { return NotesScreenModel() }
        PreviewNotesAPI.preloadSampleImages()
        return NotesScreenModel(store: NotesStore(api: PreviewNotesAPI())) { editor in editor.adopt(PreviewNotesAPI.openNote(editor.id)) }
    }
}

// MARK: Sample lists

/// A stand-in server for the Lists screen when `-shellPreview YES` is on: a few lists in memory.
/// `-listsSelect 1` opens a list (ids 1 to 3; 3 is shared with you), `-listsNew YES` opens the new form.
@MainActor
final class PreviewListsAPI: ListsAPI {
    private var mine: [ListDetail]
    private var shared: [ListDetail]
    private var nextId = 100
    private let people: [ListDetail.SharedUser] = [.init(id: 7, username: "sam", displayName: "Sam Lee"), .init(id: 8, username: "sasha", displayName: "Sasha Kim")]

    init() {
        func item(_ id: Int, _ text: String, _ checked: Bool = false, _ position: Int) -> ListEntry { ListEntry(id: id, text: text, checked: checked, position: position) }
        mine = [
            ListDetail(id: 1, title: "Groceries", isOwner: true, owner: nil, items: [
                item(11, "Oat milk", false, 0), item(12, "Eggs", false, 1), item(13, "Sourdough", true, 2), item(14, "Strawberry jam", false, 3), item(15, "Coffee beans", true, 4),
            ], sharedWith: [people[0]]),
            ListDetail(id: 2, title: "Packing for Lisbon", isOwner: true, owner: nil, items: [], sharedWith: []),
        ]
        shared = [ListDetail(id: 3, title: "Camping trip", isOwner: false, owner: "Sam Lee", items: [item(31, "Tent", false, 0), item(32, "Stove", true, 1)], sharedWith: [])]
    }

    private func summary(_ d: ListDetail) -> ListSummary {
        ListSummary(id: d.id, title: d.title, createdAt: Date(), isOwner: d.isOwner, owner: d.owner, itemCount: d.items.count, openCount: d.items.filter { !$0.checked }.count)
    }
    private func mineIndex(_ id: Int) -> Int? { mine.firstIndex { $0.id == id } }

    func lists() async throws -> ListsResponse { ListsResponse(lists: mine.map(summary), shared: shared.map(summary)) }
    func detail(id: Int) async throws -> ListDetail { (mine + shared).first { $0.id == id } ?? mine[0] }
    func create(title: String) async throws -> ListSummary {
        nextId += 1
        let d = ListDetail(id: nextId, title: title, isOwner: true, owner: nil, items: [], sharedWith: [])
        mine.insert(d, at: 0)
        return summary(d)
    }
    func rename(id: Int, title: String) async throws {
        guard let i = mineIndex(id) else { return }
        let d = mine[i]
        mine[i] = ListDetail(id: id, title: title, isOwner: true, owner: nil, items: d.items, sharedWith: d.sharedWith)
    }
    func delete(id: Int) async throws { mine.removeAll { $0.id == id } }
    func addItem(listID: Int, text: String) async throws -> ListEntry {
        nextId += 1
        let e = ListEntry(id: nextId, text: text, checked: false, position: mine[mineIndex(listID) ?? 0].items.count)
        mine[mineIndex(listID) ?? 0].items.append(e)
        return e
    }
    func toggle(listID: Int, itemID: Int) async throws -> Bool {
        guard let l = mineIndex(listID), let i = mine[l].items.firstIndex(where: { $0.id == itemID }) else { return false }
        mine[l].items[i].checked.toggle()
        return mine[l].items[i].checked
    }
    func editItem(listID: Int, itemID: Int, text: String) async throws {
        guard let l = mineIndex(listID), let i = mine[l].items.firstIndex(where: { $0.id == itemID }) else { return }
        mine[l].items[i].text = text
    }
    func deleteItem(listID: Int, itemID: Int) async throws { if let l = mineIndex(listID) { mine[l].items.removeAll { $0.id == itemID } } }
    func reorder(listID: Int, ids: [Int]) async throws {}
    func share(listID: Int, username: String) async throws {
        guard let l = mineIndex(listID), let p = people.first(where: { $0.username == username }) else { throw APIError.server("User \"\(username)\" not found") }
        let d = mine[l]
        mine[l] = ListDetail(id: d.id, title: d.title, isOwner: true, owner: nil, items: d.items, sharedWith: d.sharedWith + [p])
    }
    func unshare(listID: Int, userID: Int) async throws {
        guard let l = mineIndex(listID) else { return }
        let d = mine[l]
        mine[l] = ListDetail(id: d.id, title: d.title, isOwner: true, owner: nil, items: d.items, sharedWith: d.sharedWith.filter { $0.id != userID })
    }
    func shareable() async throws -> [ListDetail.SharedUser] { people }
}

extension ListsScreenModel {
    /// The screen's model: against the sample server when `-shellPreview YES` is on, otherwise the real one
    static func make() -> ListsScreenModel {
        UserDefaults.standard.bool(forKey: "shellPreview") ? ListsScreenModel(store: ListsStore(api: PreviewListsAPI())) : ListsScreenModel()
    }
}


// MARK: Sample bookmarks

/// A stand-in server for the Bookmarks screen when `-shellPreview YES` is on: a few bookmarks in memory.
/// `-bookmarksSelect 1` selects rows (ids 1 to 6), `-bookmarksNew YES` opens the new form, `-bookmarksTag work`,
/// `-bookmarksSort title`, `-bookmarksSearch text`, `-bookmarksShare YES` (with one row selected) opens the Share box.
@MainActor
final class PreviewBookmarksAPI: BookmarksAPI {
    private var items: [Bookmark]
    private var nextId = 100
    private let people: [ListDetail.SharedUser] = [.init(id: 7, username: "sam", displayName: "Sam Lee"), .init(id: 8, username: "sasha", displayName: "Sasha Kim")]

    init() {
        let now = Date()
        func b(_ id: Int, _ url: String, _ title: String?, _ note: String?, _ tags: [String], _ daysAgo: Double) -> Bookmark {
            Bookmark(id: id, url: url, title: title, description: note, tags: tags, createdAt: now.addingTimeInterval(-daysAgo * 86400))
        }
        items = [
            b(1, "https://www.swift.org/documentation/", "Swift documentation", "The language guide and API reference.", ["work", "reference"], 1),
            b(2, "https://react.dev", "React docs", nil, ["work", "reference"], 3),
            b(3, "https://www.theverge.com/2026/11/10/some-long-article-slug", "A long article about something", "Read this on the weekend.", ["read"], 6),
            b(4, "https://example.org/recipes/sourdough", nil, nil, [], 12),
            b(5, "https://www.recurse.com", "Recurse Center", "Programmer retreat.", ["read"], 20),
            b(6, "https://news.ycombinator.com", "Hacker News", nil, ["read"], 40),
        ]
    }

    func list() async throws -> BookmarksResponse { BookmarksResponse(bookmarks: items, tags: []) }
    func allTags() async throws -> [String] { ["work", "reference", "read", "recipes", "travel"] }
    func create(_ d: BookmarkDraft) async throws -> Bookmark {
        nextId += 1
        let b = Bookmark(id: nextId, url: d.url.hasPrefix("http") ? d.url : "https://" + d.url, title: d.title.isEmpty ? nil : d.title,
                         description: d.description.isEmpty ? nil : d.description, tags: d.tags, createdAt: Date())
        items.insert(b, at: 0)
        return b
    }
    func update(id: Int, _ d: BookmarkDraft) async throws {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i] = Bookmark(id: id, url: d.url, title: d.title.isEmpty ? nil : d.title, description: d.description.isEmpty ? nil : d.description, tags: d.tags, createdAt: items[i].createdAt)
    }
    func delete(id: Int) async throws { items.removeAll { $0.id == id } }
    func deleteMany(ids: [Int]) async throws -> Int { let n = items.count; items.removeAll { ids.contains($0.id) }; return n - items.count }
    func send(id: Int, username: String) async throws -> String {
        guard people.contains(where: { $0.username == username }) else { throw APIError.server("No user found with username \"\(username)\"") }
        return "Sent to @\(username)"
    }
    func shareable() async throws -> [ListDetail.SharedUser] { people }
}

extension BookmarksScreenModel {
    /// The screen's model: against the sample server when `-shellPreview YES` is on, otherwise the real one
    static func make() -> BookmarksScreenModel {
        UserDefaults.standard.bool(forKey: "shellPreview") ? BookmarksScreenModel(store: BookmarksStore(api: PreviewBookmarksAPI())) : BookmarksScreenModel()
    }
}


// MARK: Sample calendar

/// A stand-in server for the Calendar screen when `-shellPreview YES` is on: events around today, in memory.
/// `-calendarMode month`, `-calendarDay 2026-12-03`, `-calendarSelect 3` (ids 1 to 12; 3 and 4 are yours, the rest are synced),
/// `-calendarEdit YES`, `-calendarNew YES`, `-calendarSources none` (the "No calendars connected" notice).
@MainActor
final class PreviewCalendarAPI: CalendarAPI {
    private var all: [CalendarEvent] = []
    private var nextId = 100
    private let today = Fmt.ymd(.now)

    init() {
        let monday = CalendarMath.monday(of: today)
        func at(_ offset: Int) -> String { CalendarMath.addDays(monday, offset) }
        func e(_ id: Int, _ title: String, _ day: String, _ start: String?, _ end: String?, _ color: String, calendar: String, mine: Bool = false,
               location: String? = nil, notes: String? = nil, url: String? = nil) -> CalendarEvent {
            let base = CalendarMath.date(day) ?? .now
            let minutes = (start.flatMap { Int($0.prefix(2)) } ?? 0) * 60
            return CalendarEvent(id: id, title: title, startAt: base.addingTimeInterval(Double(minutes) * 60), endAt: base.addingTimeInterval(Double(minutes + 60) * 60),
                                 allDay: start == nil, location: location, description: notes, url: url, calendarName: calendar, color: color, day: day,
                                 editable: mine, deletable: mine, startTime: start, endTime: end)
        }
        all = [
            e(1, "Team sync", at(0), "09:30", "10:00", "#6366f1", calendar: "Work", location: "Room 4", url: "https://meet.example.com/sync"),
            e(2, "Dentist", at(1), "14:00", "15:00", "#ec4899", calendar: "Family"),
            e(3, "Lunch with Sam", at(2), "12:30", "13:30", "#10b981", calendar: "Local only", mine: true, location: "The corner café", notes: "Bring the book.\nSplit the bill."),
            e(4, "Launch day", at(2), nil, nil, "#f59e0b", calendar: "Local only", mine: true),
            e(5, "Design review", at(2), "16:00", "17:00", "#6366f1", calendar: "Work"),
            e(6, "Gym", at(3), "07:00", "08:00", "#10b981", calendar: "Family"),
            e(7, "Board meeting", at(4), "10:00", "12:00", "#6366f1", calendar: "Work", notes: "[vT] Quarterly numbers"),
            e(8, "Movie night", at(5), "19:30", "21:30", "#ec4899", calendar: "Family"),
            e(9, "Standup", at(7), "09:00", "09:15", "#6366f1", calendar: "Work"),
            e(10, "Standup", at(8), "09:00", "09:15", "#6366f1", calendar: "Work"),
            e(11, "Standup", at(9), "09:00", "09:15", "#6366f1", calendar: "Work"),
            e(12, "Offsite", at(9), nil, nil, "#f59e0b", calendar: "Work"),
            e(13, "Retro", at(9), "15:00", "16:00", "#6366f1", calendar: "Work"),
            e(14, "Call mum", at(9), "18:00", "18:30", "#10b981", calendar: "Family"),
        ]
    }

    func events(from: String, days: Int) async throws -> CalendarResponse {
        let to = CalendarMath.addDays(from, days)
        let none = UserDefaults.standard.string(forKey: "calendarSources") == "none"
        let sources = none ? [] : [CalendarSourceInfo(name: "Work", color: "#6366f1", lastSynced: Date().addingTimeInterval(-600)),
                                   CalendarSourceInfo(name: "Family", color: "#ec4899", lastSynced: Date().addingTimeInterval(-3600))]
        return CalendarResponse(from: from, days: days, today: today, events: all.filter { $0.day >= from && $0.day < to }, sources: sources)
    }
    func choices() async throws -> CalendarChoices {
        CalendarChoices(calendars: [CalendarChoice(value: "local", label: "Local only", color: "#374151"), CalendarChoice(value: "1|caldav|x", label: "Work", color: "#6366f1")], defaultTarget: "local")
    }
    func create(_ d: EventDraft) async throws {
        nextId += 1
        all.append(CalendarEvent(id: nextId, title: d.title, startAt: CalendarMath.date(d.date) ?? .now, endAt: CalendarMath.date(d.date) ?? .now, allDay: d.allDay,
                                 location: d.location.isEmpty ? nil : d.location, description: d.description.isEmpty ? nil : d.description, url: nil, calendarName: "Local only",
                                 color: "#374151", day: d.date, editable: true, deletable: true, startTime: d.allDay ? nil : d.startTime, endTime: d.allDay ? nil : d.endTime))
    }
    func update(id: Int, _ d: EventDraft) async throws {
        guard let i = all.firstIndex(where: { $0.id == id }) else { return }
        let o = all[i]
        all[i] = CalendarEvent(id: id, title: d.title, startAt: o.startAt, endAt: o.endAt, allDay: d.allDay, location: d.location.isEmpty ? nil : d.location,
                               description: d.description.isEmpty ? nil : d.description, url: o.url, calendarName: o.calendarName, color: o.color, day: d.date,
                               editable: true, deletable: true, startTime: d.allDay ? nil : d.startTime, endTime: d.allDay ? nil : d.endTime)
    }
    func delete(id: Int) async throws { all.removeAll { $0.id == id } }
}

extension CalendarScreenModel {
    /// The screen's model: against the sample server when `-shellPreview YES` is on, otherwise the real one
    static func make() -> CalendarScreenModel {
        UserDefaults.standard.bool(forKey: "shellPreview") ? CalendarScreenModel(store: CalendarStore(api: PreviewCalendarAPI())) : CalendarScreenModel()
    }
}

// MARK: Sample analytics

/// A stand-in server for the Analytics screen when `-shellPreview YES` is on. `-analyticsSample full` (the default),
/// `few` (three completions: the small-sample notice), `empty` (nothing yet). `-analyticsRange 90` starts on that range.
@MainActor
final class PreviewAnalyticsAPI: AnalyticsAPI {
    func load(range: String) async throws -> Analytics {
        let sample = UserDefaults.standard.string(forKey: "analyticsSample") ?? "full"
        let none = sample == "empty", few = sample == "few"
        let weeks = (0..<12).map { i -> String in
            let v = none ? [0, 0, 0, 0, 0, 0] : few ? [i == 11 ? 1 : 0, i == 11 ? 2 : 0, 0, 0, 0, 0] : [1 + i % 3, 2 + i % 4, i % 2, (i + 1) % 3, i % 4 == 0 ? 1 : 0, i == 3 ? 2 : 0]
            return "{\"label\":\"Aug \(3 + i)\",\"early\":\(v[0]),\"on_time\":\(v[1]),\"late_same_day\":\(v[2]),\"late_1_3\":\(v[3]),\"late_4_7\":\(v[4]),\"late_8plus\":\(v[5])}"
        }.joined(separator: ",")
        let trend = (0..<12).map { i in "{\"label\":\"Aug \(3 + i)\",\"rate\":\(i == 5 ? "null" : "\(55 + (i * 7) % 40)"),\"total\":\(i == 5 ? 0 : 6 + i % 5)}" }.joined(separator: ",")
        let hours = ["6am", "7am", "8am", "9am", "10am", "11am", "12pm", "1pm", "2pm", "3pm", "4pm", "5pm"]
        let tod = hours.enumerated().map { "{\"label\":\"\($0.element)\",\"count\":\(none ? 0 : [1, 3, 6, 9, 7, 4, 2, 3, 5, 6, 4, 2][$0.offset])}" }.joined(separator: ",")
        let velocity = (0..<12).map { i in "{\"label\":\"Aug \(3 + i)\",\"count\":\(6 + (i * 5) % 9)}" }.joined(separator: ",")
        let days = ["M", "T", "W", "T", "F", "S", "S"]
        let heat = (0..<12).map { w in
            "[" + (0..<7).map { d in
                let c = (w * 3 + d * 5) % 7 > 3 ? (w + d) % 5 : 0
                let future = w == 11 && d > 3
                return "{\"dateStr\":\"2026-08-\(10 + d)\",\"isFuture\":\(future),\"count\":\(c),\"intensity\":\(min(4, c)),\"title\":\"Day \(w * 7 + d): \(c)\"}"
            }.joined(separator: ",") + "]"
        }.joined(separator: ",")
        let weekLabels = (0..<12).map { "\"Aug \(3 + $0 * 7 % 28)\"" }.joined(separator: ",")
        let routines = none ? "[]" : """
        [{"id":3,"title":"Evening stretch","frequency":"daily","specificTime":"21:00","expected":30,"completed":11,"rate":37,"streakCurrent":0,"streakBest":6,"streakCount":4,"streakAvg":3,"lastBroken":{"length":2,"endDate":"2026-11-08T00:00:00.000Z"},"specificTimeRate":45,"timedSampleSize":11,"topStreaks":[{"length":6,"startDate":"2026-10-02","endDate":"2026-10-07","isActive":false},{"length":4,"startDate":"2026-10-20","endDate":"2026-10-23","isActive":false}]},
         {"id":2,"title":"Weekly review","frequency":"weekly","specificTime":null,"expected":4,"completed":3,"rate":75,"streakCurrent":2,"streakBest":5,"streakCount":2,"streakAvg":3,"lastBroken":null,"specificTimeRate":null,"timedSampleSize":0,"topStreaks":[]},
         {"id":1,"title":"Morning pages","frequency":"daily","specificTime":null,"expected":30,"completed":28,"rate":93,"streakCurrent":12,"streakBest":21,"streakCount":3,"streakAvg":11,"lastBroken":null,"specificTimeRate":null,"timedSampleSize":0,"topStreaks":[]}]
        """
        let routineVel = none ? "[]" : (0..<8).map { "{\"label\":\"Sep \(7 + $0)\",\"expected\":14,\"completed\":\(6 + ($0 * 3) % 8),\"rate\":\(45 + ($0 * 9) % 50)}" }.joined(separator: ",").wrapped
        let found = none ? "[]" : """
        [{"tone":"warn","href":"/routines/3","text":"Evening stretch is slipping: 11 of 30 days done in the last month."},
         {"tone":"good","href":"/routines/1","text":"Morning pages is going well: a 12-day streak."},
         {"tone":"warn","href":"/tasks?view=overdue","text":"4 tasks are overdue."},
         {"tone":"neutral","href":null,"text":"You finish most things between 9am and 10am."}]
        """
        let json = """
        {"range":"\(range)","rangeLabel":"\(range == "all" ? "All time" : "Last \(range) days")",
         "summary":{"total":\(none ? 0 : few ? 3 : 64),"withDueCount":\(none ? 0 : 41),"trueOnTimeRate":\(none ? "null" : "78"),"sameDayRate":\(none ? "null" : "88"),"avgDaysLate":\(none ? "null" : "2.4"),"topDay":\(none ? "null" : "\"Tuesday\""),"topDayCount":\(none ? 0 : 14)},
         "streak":{"current":\(none ? 0 : 5),"best":\(none ? 0 : 17)},
         "weeklyData":[\(weeks)],
         "onTimeRateTrend":[\(trend)],"hasOnTimeRateTrend":\(!none && !few),
         "todData":[\(tod)],"hasTodData":\(!none),
         "lateAgeStats":\(none ? "null" : "{\"count\":2,\"avg\":11.5,\"median\":11.5,\"max\":14}"),
         "velocityData":[\(velocity)],"velocityTrend":"up","hasVelocityData":\(!none),
         "priorityData":[{"priority":"high","label":"High","total":\(none ? 0 : 12),"trueRate":58,"sdRate":75},{"priority":"medium","label":"Medium","total":\(none ? 0 : 20),"trueRate":85,"sdRate":85},{"priority":"low","label":"Low","total":\(none ? 0 : 9),"trueRate":44,"sdRate":60},{"priority":"none","label":"None","total":0,"trueRate":null,"sdRate":null}],
         "heatmap":{"weeks":[\(heat)],"dayLabels":\(days.map { "\"\($0)\"" }.joined(separator: ",").wrapped),"weekLabels":[\(weekLabels)]},
         "routineStats":{"overallRate":\(none ? "null" : "68"),"totalExpected":64,"totalCompleted":42,"byRoutine":\(routines)},
         "routineVelData":\(routineVel),"hasRoutineVelData":\(!none),
         "standsOut":\(found),"standsOutByAi":\(sample == "ai")}
        """
        return try JSONDecoder().decode(Analytics.self, from: Data(json.utf8))
    }
}

private extension String { var wrapped: String { "[" + self + "]" } }

extension MacDebug {
    static func analyticsStore() -> AnalyticsStore {
        guard UserDefaults.standard.bool(forKey: "shellPreview") else { return AnalyticsStore() }
        let r = AnalyticsRange(rawValue: UserDefaults.standard.string(forKey: "analyticsRange") ?? "")
        return AnalyticsStore(api: PreviewAnalyticsAPI(), range: r)
    }
}
#endif

#if DEBUG
// MARK: Sample chat

/// A stand-in server for the AI Chat screen when `-shellPreview YES` is on. `-chatSample thread` (the default),
/// `empty`, `slow` (a reply that never arrives: the typing dots), `fail` (the daily limit message).
/// `-chatInput "words"` fills the box, `-chatSend YES` sends it, `-aiOff YES` is a server without AI.
@MainActor
final class PreviewChatAPI: ChatAPI {
    private let sample = UserDefaults.standard.string(forKey: "chatSample") ?? "thread"
    private var sent: [ChatMessage] = []

    func thread() async throws -> [ChatMessage] {
        guard sample != "empty" else { return [] }
        return [
            ChatMessage(role: "user", content: "What tasks are slipping this week?"),
            ChatMessage(role: "assistant", content: "Three tasks are overdue:\n• Send the quarterly report (due Monday)\n• Renew the domain (due Tuesday)\n• Book the dentist (due Wednesday)\n\nThe report is the one that has moved the most: it was due last Friday and is now four days late."),
            ChatMessage(role: "user", content: "Move the dentist one to next week."),
            ChatMessage(role: "assistant", content: "I can only read your data, so I can't change the due date. You can move it yourself from Tasks."),
        ]
    }
    func send(_ message: String) async throws -> ChatReply {
        if sample == "slow" { try await Task.sleep(for: .seconds(600)) }
        if sample == "fail" { throw NSError(domain: "chat", code: 1, userInfo: [NSLocalizedDescriptionKey: "Daily limit of 50 messages reached. Resets at midnight."]) }
        return ChatReply(reply: "This is a sample reply to: \(message)", remaining: 41)
    }
    func clear() async throws {}
}

extension MacDebug {
    static func chatStore() -> ChatStore {
        UserDefaults.standard.bool(forKey: "shellPreview") ? ChatStore(api: PreviewChatAPI()) : ChatStore()
    }
}
#endif

#if DEBUG
// MARK: Sample search

/// A stand-in server for the search palette when `-shellPreview YES` is on. `-searchSample full` (the default),
/// `empty` (no hits) or `fail`.
@MainActor
final class PreviewSearchAPI: SearchAPI {
    private let sample = UserDefaults.standard.string(forKey: "searchSample") ?? "full"

    func search(_ query: String) async throws -> [SearchResponse.Group] {
        if sample == "fail" { throw NSError(domain: "search", code: 1) }
        if sample == "empty" { return [] }
        return [
            .init(group: "Notes", items: [
                .init(type: "note", id: 1, title: "Trip plan: Lisbon in March", subtitle: "travel, planning"),
                .init(type: "note", id: 2, title: "Packing list for the trip", subtitle: "note")]),
            .init(group: "Tasks", items: [.init(type: "task", id: 3, title: "Book the trip flights", subtitle: "due 2026-12-01")]),
            .init(group: "Reminders", items: [.init(type: "reminder", id: 4, title: "Renew passport before the trip", subtitle: "2026-11-20")]),
            .init(group: "Routines", items: [.init(type: "routine", id: 5, title: "Stretch (trip recovery)", subtitle: "daily · evening")]),
            .init(group: "Calendar", items: [.init(type: "calendar", id: 6, title: "Flight to Lisbon", subtitle: "Mar 3, 2027, 9:30 AM")]),
            .init(group: "Lists", items: [.init(type: "list", id: 7, title: "Trip packing", subtitle: "12 items")]),
            .init(group: "Bookmarks", items: [.init(type: "bookmark", id: 8, title: "Lisbon travel guide", subtitle: "travel, reference")]),
        ]
    }
    func event(id: Int) async throws -> CalendarEvent { throw NSError(domain: "search", code: 2) }
}

extension MacDebug {
    static func searchStore() -> SearchStore {
        UserDefaults.standard.bool(forKey: "shellPreview") ? SearchStore(api: PreviewSearchAPI()) : SearchStore()
    }
}
#endif

#if DEBUG
import WebKit

// MARK: Sample help

/// A stand-in server for the Help window when `-shellPreview YES` is on: a few sections in the web's markup.
@MainActor
final class PreviewHelpAPI: HelpAPI {
    func help() async throws -> HelpContent {
        func section(_ id: String, _ title: String, _ body: String) -> String {
            "<section id=\"\(id)\"><div class=\"bg-gray-900\"><h2>\(title)</h2>\(body)</div></section>"
        }
        let filler = "<p>This is made-up help text so the layout can be checked. Press <span class=\"help-kbd\">C</span> from anywhere to capture something, then review it before saving.</p>"
        let list = "<h3>Views</h3><ul><li><strong>Inbox</strong> — new tasks land here.</li><li><strong>Today</strong> — what you plan to do today.</li><li>Use <code>#tags</code> to group tasks. See <a href=\"#notes\">Notes</a>.</li></ul>"
        let items = [("capture", "Capture"), ("today", "Today"), ("tasks", "Tasks"), ("notes", "Notes"), ("reminders", "Reminders"), ("routines", "Routines"),
                     ("calendar", "Calendar"), ("lists", "Lists"), ("bookmarks", "Bookmarks"), ("analytics", "Analytics"), ("ai", "AI Chat"),
                     ("settings", "Settings"), ("data", "Import &amp; Export"), ("search", "Global Search"), ("mobile", "Mobile")]
        let html = items.map { section($0.0, $0.1, filler + list + (($0.0 == "settings") ? "<p>Sign in with Apple needs your <a href=\"https://appleid.apple.com\">Apple ID</a>.</p>" : "")) }.joined(separator: "\n")
        return HelpContent(sections: items.map { .init(id: $0.0, title: $0.1.replacingOccurrences(of: "&amp;", with: "&")) }, html: html)
    }
}

extension MacDebug {
    static func helpStore() -> HelpStore {
        let store = UserDefaults.standard.bool(forKey: "shellPreview") ? HelpStore(api: PreviewHelpAPI()) : HelpStore()
        return store
    }

    /// `-helpSnapshot help.png`: once the text has loaded, draws the Help window (native parts and the web view) to a PNG
    /// in the app's temporary folder and quits. `-helpScroll tasks` scrolls to a section first.
    static func helpReady(_ web: WKWebView) {
        let d = UserDefaults.standard
        guard let name = d.string(forKey: "helpSnapshot") else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            if let id = d.string(forKey: "helpScroll") {
                _ = try? await web.evaluateJavaScript("document.getElementById('\(id)').scrollIntoView()")
                try? await Task.sleep(for: .seconds(1))
            }
            if let q = d.string(forKey: "helpFind") { web.find(q) { _ in }; try? await Task.sleep(for: .seconds(1)) }
            guard let view = web.window?.contentView else { NSApp.terminate(nil); return }
            let file = name.hasPrefix("/") ? name : NSTemporaryDirectory() + name
            guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { NSApp.terminate(nil); return }
            view.cacheDisplay(in: view.bounds, to: rep)
            let base = NSImage(size: view.bounds.size)
            base.addRepresentation(rep)
            if let snap = try? await web.takeSnapshot(configuration: nil) {
                let r = view.convert(web.bounds, from: web)
                base.lockFocus()
                snap.draw(in: NSRect(x: r.minX, y: view.isFlipped ? view.bounds.height - r.maxY : r.minY, width: r.width, height: r.height))
                base.unlockFocus()
            }
            if let tiff = base.tiffRepresentation, let out = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                try? out.write(to: URL(fileURLWithPath: file))
            }
            NSApp.terminate(nil)
        }
    }
}
#endif

#if DEBUG
// MARK: Sample settings

/// A stand-in server for the Settings window when `-shellPreview YES` is on: everything in memory. Open it with
/// `-settingsOpen YES -settingsTab account|modules|notifications|appearance|notes|dashboard|tags|shortcuts|data`
/// and draw it with `-settingsSnapshot settings.png` (then it quits). `-settingsTheme custom` starts on that theme.
@MainActor
final class PreviewSettingsAPI: SettingsAPI {
    private var data: SettingsData
    private var notif: NotificationSettings
    private var notes = NotesPrefs(autosaveEnabled: true, autosaveDuration: "2min", hasPin: true, notePaper: "theme")
    private var tagList = [SettingsTag(name: "errands", count: 4), SettingsTag(name: "health", count: 12), SettingsTag(name: "home", count: 7), SettingsTag(name: "work", count: 21)]
    private var tokenList: [ApiTokenItem] = []
    private var sessionList: [DeviceSession] = []

    init() {
        let d = UserDefaults.standard
        let names = [("dashboard", "Today", true), ("capture", "Capture", false), ("tasks", "Tasks", false), ("reminders", "Reminders", false), ("routines", "Routines", false),
                     ("notes", "Notes", false), ("lists", "Lists", false), ("bookmarks", "Bookmarks", false), ("calendar", "Calendar", false), ("analytics", "Analytics", false),
                     ("ai", "AI Chat", false), ("settings", "Settings", true)]
        let modules = names.map { "{\"key\":\"\($0.0)\",\"label\":\"\($0.1)\",\"alwaysEnabled\":\($0.2),\"enabled\":\($0.0 != "lists")}" }.joined(separator: ",")
        let theme = d.string(forKey: "settingsTheme") ?? d.string(forKey: "galleryTheme") ?? "dark"
        let json = """
        {"account":{"displayName":"Sample Person","username":"sample","email":"sample@example.com","timezone":"America/Chicago","timeFormat":"12h","avatarUrl":null,"hasCustomAvatar":false,"hasPassword":true,"passwordLogin":true},
         "modules":[\(modules)],
         "appearance":{"theme":"\(theme)","customAccent":"#10b981","customBase":"dark","statusColors":"catppuccin"},
         "dashboard":[{"key":"focus","enabled":true,"label":"My Focus","description":"Tasks set to \\"Today\\" status"},{"key":"calendar","enabled":true,"label":"Calendar","description":"Today's events from your calendars"},
                      {"key":"due_items","enabled":true,"label":"Due Today & Overdue","description":"Open tasks and reminders that are due"},{"key":"routines","enabled":false,"label":"Routines","description":"Today's habits and streaks"},
                      {"key":"resurfaced","enabled":true,"label":"Resurfacing","description":"A past note surfaced daily for reflection"},{"key":"review","enabled":true,"label":"Needs Review","description":"Notes flagged for review"}]}
        """
        data = try! JSONDecoder().decode(SettingsData.self, from: Data(json.utf8))
        let n = """
        {"pushoverAvailable":true,"pushoverKey":"u1b2c3","pushoverEnabled":true,"ntfyAvailable":true,"ntfyServer":"https://ntfy.example.com","ntfyEnabled":true,"ntfyTopic":"obelo-7f3a91c2",
         "emailAvailable":true,"accountEmail":"sample@example.com","notifEmail":"",
         "types":{"daily_digest":{"enabled":true,"sendTime":"07:30","channels":{"pushover":true,"email":true,"ntfy":false}},
                  "slipping_tasks":{"enabled":false,"sendTime":"09:00","channels":{"pushover":true,"email":false,"ntfy":false}},
                  "task_due":{"enabled":true,"sendTime":"","channels":{"pushover":true,"email":false,"ntfy":true}}}}
        """
        notif = try! JSONDecoder().decode(NotificationSettings.self, from: Data(n.utf8))
        let s = "[{\"key\":\"a\",\"current\":true,\"device\":\"Safari on Mac\",\"ip\":\"192.168.1.20\",\"signedInAt\":\"2026-11-14T15:20:00.000Z\",\"lastSeenAt\":\"2026-11-15T21:00:00.000Z\"},{\"key\":\"b\",\"current\":false,\"device\":\"Obelo on iPhone\",\"ip\":null,\"signedInAt\":\"2026-11-02T09:10:00.000Z\",\"lastSeenAt\":\"2026-11-15T08:00:00.000Z\"}]"
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        sessionList = (try? dec.decode([DeviceSession].self, from: Data(s.utf8))) ?? []
        if d.string(forKey: "settingsTokens") != "none" {
            tokenList = [ApiTokenItem(id: 1, label: "iPhone Shortcut", createdAt: .now.addingTimeInterval(-86_400 * 20), lastUsed: .now.addingTimeInterval(-3_600)),
                         ApiTokenItem(id: 2, label: "iPad Shortcut", createdAt: .now.addingTimeInterval(-86_400 * 3), lastUsed: nil)]
        }
    }

    func settings() async throws -> SettingsData { data }
    func saveAccount(displayName: String, email: String, timezone: String, timeFormat: String) async throws {
        data.account.displayName = displayName; data.account.email = email; data.account.timezone = timezone; data.account.timeFormat = timeFormat
    }
    func changePassword(current: String, new: String) async throws { data.account.hasPassword = true }
    func sessions() async throws -> [DeviceSession] { sessionList }
    func endSession(key: String) async throws { sessionList.removeAll { $0.key == key } }
    func endOtherSessions() async throws -> Int { let n = sessionList.filter { !$0.current }.count; sessionList.removeAll { !$0.current }; return n }
    func uploadAvatar(_ data: Data, filename: String) async throws {}
    func removeAvatar() async throws {}
    func saveModules(_ list: [(key: String, enabled: Bool)]) async throws {
        data.modules = list.compactMap { item in data.modules.first { $0.key == item.key }.map { var m = $0; m.enabled = item.enabled; return m } }
    }
    func saveAppearance(theme: String, customAccent: String, customBase: String, statusColors: String) async throws {
        data.appearance = .init(theme: theme, customAccent: customAccent, customBase: customBase, statusColors: statusColors)
    }
    func saveDashboard(_ list: [(key: String, enabled: Bool)]) async throws {
        data.dashboard = list.compactMap { item in data.dashboard.first { $0.key == item.key }.map { var w = $0; w.enabled = item.enabled; return w } }
    }
    func deleteAccount(confirmUsername: String) async throws {}
    func notifications() async throws -> NotificationSettings { notif }
    func saveNotifications(_ s: NotificationSettings) async throws { notif = s }
    func testNotification(_ which: String) async throws -> String { "Test \(which.replacingOccurrences(of: "test-", with: "")) sent" }
    func newNtfyTopic() async throws -> String { "obelo-\(Int.random(in: 100000...999999))" }
    func notesPrefs() async throws -> NotesPrefs { notes }
    func saveNotesPrefs(_ p: NotesPrefs) async throws { notes = p }
    func setPin(current: String, new: String, confirm: String) async throws -> String { notes.hasPin = true; return "Note lock PIN saved" }
    func removePin(current: String) async throws -> String { notes.hasPin = false; return "Note lock PIN removed" }
    func tags() async throws -> [SettingsTag] { tagList }
    func createTag(_ name: String) async throws { tagList.append(SettingsTag(name: name, count: 0)) }
    func renameTag(from old: String, to new: String) async throws { tagList = tagList.map { $0.name == old ? SettingsTag(name: new, count: $0.count) : $0 } }
    func deleteTag(_ name: String) async throws { tagList.removeAll { $0.name == name } }
    func export(_ name: String) async throws -> Data { Data("{}".utf8) }
    func importFiles(_ kind: ImportKind, _ files: [APIClient.UploadFile]) async throws -> String { "Imported \(files.count) file\(files.count == 1 ? "" : "s")" }
    func apiTokens() async throws -> [ApiTokenItem] { tokenList }
    func createApiToken(label: String) async throws -> ApiTokenItem {
        let t = ApiTokenItem(id: (tokenList.map(\.id).max() ?? 0) + 1, label: label.isEmpty ? "iOS Shortcut" : label, createdAt: .now, lastUsed: nil, token: String(repeating: "9f2c4e7a", count: 8))
        tokenList.append(ApiTokenItem(id: t.id, label: t.label, createdAt: t.createdAt, lastUsed: nil))
        return t
    }
    func revokeApiToken(id: Int) async throws { tokenList.removeAll { $0.id == id } }
}

extension MacDebug {
    static func settingsHub() -> SettingsHub {
        UserDefaults.standard.bool(forKey: "shellPreview")
            ? SettingsHub(api: PreviewSettingsAPI(), calendars: CalendarSourcesStore(api: PreviewCalendarSourcesAPI()))
            : SettingsHub()
    }

    /// `-settingsSnapshot settings.png`: after the window has loaded, draws it to a PNG in the app's temporary folder and quits
    static func settingsSnapshotIfAsked() {
        guard let name = UserDefaults.standard.string(forKey: "settingsSnapshot") else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.5))
            let window = NSApp.windows.first { !MacWindowConfigurator.isMain($0) && $0.isVisible && $0.title != "Kit Gallery" && $0.styleMask.contains(.titled) }
            // `-settingsHeight 1500` makes the window taller first, to see a long tab in one picture
            let tall = UserDefaults.standard.double(forKey: "settingsHeight")
            if tall > 0, let window {
                window.setContentSize(NSSize(width: window.contentLayoutRect.width, height: tall))
                try? await Task.sleep(for: .seconds(1))
            }
            if let view = window?.contentView?.superview, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: rep)
                let file = name.hasPrefix("/") ? name : NSTemporaryDirectory() + name
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: file))
            }
            NSApp.terminate(nil)
        }
    }
}

// MARK: Sample calendar accounts

/// A stand-in server for Settings ▸ Calendars when `-shellPreview YES` is on. `-calendarsState empty` shows no accounts or
/// shared calendars; `-calendarsFail YES` makes Connect answer with the error the web shows.
@MainActor
final class PreviewCalendarSourcesAPI: CalendarSourcesAPI {
    private var accounts: [CalendarAccount]
    private var own: [OwnCalendar]
    private var defaultTarget = "local"
    private let fail = UserDefaults.standard.bool(forKey: "calendarsFail")
    private let people = [ShareableUser(id: 2, username: "sam", displayName: "Sam Rivera"), ShareableUser(id: 3, username: "jo", displayName: "Jo Lee"),
                          ShareableUser(id: 4, username: "kim", displayName: nil)]

    init() {
        if UserDefaults.standard.string(forKey: "calendarsState") == "empty" { accounts = []; own = []; return }
        accounts = [
            CalendarAccount(id: 1, type: "caldav", name: "iCloud Calendar", color: "#6366f1", active: true,
                            lastSynced: Date(timeIntervalSinceNow: -3600), isFamily: false, calendars: [
                                SourceCalendar(url: "u/home", name: "Home", color: "#22c55e", selected: true, isFamily: false),
                                SourceCalendar(url: "u/work", name: "Work", color: "#f59e0b", selected: true, isFamily: false),
                                SourceCalendar(url: "u/birthdays", name: "Birthdays", color: nil, selected: false, isFamily: false)]),
            CalendarAccount(id: 2, type: "google", name: "Google (sample@example.com)", color: "#4285f4", active: true,
                            lastSynced: nil, isFamily: true, calendars: [
                                SourceCalendar(url: "g/primary", name: "sample@example.com", color: "#4285f4", selected: true, isFamily: true)]),
        ]
        own = [OwnCalendar(id: 7, name: "Family", color: "#ec4899", members: [CalendarMember(userId: 2, username: "sam", displayName: "Sam Rivera", canEdit: true)]),
               OwnCalendar(id: 8, name: "Work Team", color: "#14b8a6", members: [])]
    }

    func overview() async throws -> CalendarSourcesOverview {
        var targets = [CalendarChoice(value: "local", label: "Local only", color: "#374151")]
        targets += accounts.map { CalendarChoice(value: "\($0.id)|caldav|", label: $0.name, color: $0.color) }
        targets += own.map { CalendarChoice(value: "local_calendar|\($0.id)", label: $0.name, color: $0.color) }
        return CalendarSourcesOverview(sources: accounts, localCalendars: own, shareableUsers: people, defaultTarget: defaultTarget,
                                       targets: targets, googleConfigured: false)
    }
    func connect(_ d: CaldavDraft) async throws -> ConnectResult {
        if fail { throw NSError(domain: "x", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not connect: 401 Unauthorized"]) }
        accounts.append(CalendarAccount(id: 9, type: "caldav", name: d.name.isEmpty ? "iCloud Calendar" : d.name, color: d.color, active: true, lastSynced: .now, isFamily: false, calendars: []))
        return ConnectResult(found: 2, synced: 14, syncError: nil)
    }
    func sync(id: Int) async throws -> SyncResult { try? await Task.sleep(for: .seconds(1)); return SyncResult(count: 14, name: accounts.first { $0.id == id }?.name ?? "") }
    func setColor(id: Int, _ color: String) async throws { if let i = accounts.firstIndex(where: { $0.id == id }) { accounts[i].color = color } }
    func remove(id: Int) async throws { accounts.removeAll { $0.id == id } }
    func setCalendars(id: Int, urls: [String]) async throws -> SelectResult {
        if let i = accounts.firstIndex(where: { $0.id == id }) { for j in accounts[i].calendars.indices { accounts[i].calendars[j].selected = urls.contains(accounts[i].calendars[j].url) } }
        return SelectResult(selected: urls.count, count: 9, syncError: nil)
    }
    func setFamily(id: Int, url: String?) async throws {}
    func setDefault(_ target: String) async throws { defaultTarget = target }
    func createLocal(name: String, color: String) async throws { own.append(OwnCalendar(id: 20 + own.count, name: name, color: color, members: [])) }
    func updateLocal(id: Int, name: String, color: String) async throws { if let i = own.firstIndex(where: { $0.id == id }) { own[i].name = name; own[i].color = color } }
    func deleteLocal(id: Int) async throws { own.removeAll { $0.id == id } }
    func addMember(calendar: Int, username: String) async throws {
        guard let p = people.first(where: { $0.username == username }) else { throw NSError(domain: "x", code: 2, userInfo: [NSLocalizedDescriptionKey: "User \"\(username)\" not found."]) }
        if let i = own.firstIndex(where: { $0.id == calendar }) { own[i].members.append(CalendarMember(userId: p.id, username: p.username, displayName: p.displayName, canEdit: true)) }
    }
    func removeMember(calendar: Int, userId: Int) async throws { if let i = own.firstIndex(where: { $0.id == calendar }) { own[i].members.removeAll { $0.userId == userId } } }
}
#endif
