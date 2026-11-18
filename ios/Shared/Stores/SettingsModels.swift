import Foundation

// What the settings calls send and receive, shared by the iPhone and iPad screens and the Mac Settings window.

struct SettingsData: Decodable {
    struct Account: Decodable {
        var displayName: String
        let username: String
        var email: String
        var timezone: String
        var timeFormat: String
        var avatarUrl: String?
        var hasCustomAvatar: Bool
        // Newer servers only; nil means the server doesn't offer password sign-in
        var hasPassword: Bool? = nil
        var passwordLogin: Bool? = nil
    }
    struct Module: Decodable, Identifiable, Equatable {
        let key: String
        let label: String
        let alwaysEnabled: Bool
        var enabled: Bool
        var id: String { key }
    }
    struct Look: Decodable, Equatable { var theme: String; var customAccent: String; var customBase: String; var statusColors: String? }
    struct Widget: Decodable, Identifiable, Equatable {
        let key: String
        var enabled: Bool
        let label: String
        let description: String
        var id: String { key }
    }
    var account: Account
    var modules: [Module]
    var appearance: Look
    var dashboard: [Widget]
}


struct NotificationSettings: Codable {
    struct Channels: Codable, Equatable { var pushover: Bool; var email: Bool; var ntfy: Bool }
    struct TypePref: Codable, Equatable { var enabled: Bool; var sendTime: String; var channels: Channels }

    let pushoverAvailable: Bool
    var pushoverKey: String
    var pushoverEnabled: Bool
    let ntfyAvailable: Bool
    let ntfyServer: String
    var ntfyEnabled: Bool
    var ntfyTopic: String
    let emailAvailable: Bool
    let accountEmail: String
    var notifEmail: String
    var types: [String: TypePref]
}


/// The Notes tab's numbers (autosave, handwriting paper, whether a lock PIN is set)
struct NotesPrefs: Decodable, Equatable {
    var autosaveEnabled: Bool
    var autosaveDuration: String
    var hasPin: Bool
    var notePaper: String? = nil
}

struct SettingsTag: Decodable, Identifiable, Equatable {
    let name: String
    let count: Int
    var id: String { name }
}

/// A key for iOS Shortcuts. `token` is the token itself, present only in the answer to creating it.
struct ApiTokenItem: Decodable, Identifiable, Equatable {
    let id: Int
    let label: String
    let createdAt: Date?
    let lastUsed: Date?
    var token: String? = nil
}

/// The web's Export your data list
struct ExportKind: Identifiable, Equatable {
    let name: String
    let title: String
    let detail: String
    var id: String { name }

    static let all = [
        ExportKind(name: "json", title: "Full data export", detail: "Everything — notes, tasks, reminders, routines, lists, bookmarks (JSON)"),
        ExportKind(name: "tasks.csv", title: "Tasks", detail: "Title, status, priority, due date, tags, notes (CSV)"),
        ExportKind(name: "notes.json", title: "Notes", detail: "All notes with markdown content, tags and metadata (JSON)"),
        ExportKind(name: "bookmarks.csv", title: "Bookmarks (CSV)", detail: "Spreadsheet-friendly"),
        ExportKind(name: "bookmarks.html", title: "Bookmarks (HTML)", detail: "Import into any browser"),
    ]

    /// "obelo-tasks-2026-11-15.csv"
    func filename(on day: String) -> String {
        let ext = name == "json" ? "json" : (name as NSString).pathExtension
        let base = name == "json" ? "export" : (name as NSString).deletingPathExtension
        return "obelo-\(base)-\(day).\(ext)"
    }
}

enum ImportKind: String, CaseIterable, Identifiable {
    case notes, tasks, json
    var id: String { rawValue }
    var title: String {
        switch self { case .notes: "Notes from Markdown"; case .tasks: "Tasks from CSV"; case .json: "Restore from JSON export" }
    }
    var detail: String {
        switch self {
        case .notes: ".md files — filename becomes the title. YAML frontmatter title: and tags: are parsed automatically."
        case .tasks: "Requires a title column. Optional: status, priority, due date, due time, tags, notes. Column names are matched flexibly."
        case .json: "Import a Obelo JSON export. Notes, tasks, and bookmarks are added alongside existing data — nothing is overwritten."
        }
    }
    var ext: String { switch self { case .notes: "md"; case .tasks: "csv"; case .json: "json" } }
    var mime: String { switch self { case .notes: "text/markdown"; case .tasks: "text/csv"; case .json: "application/json" } }
    /// The server goes by the extension, so a picked file gets the right one added when it lacks it
    func uploadName(for picked: String) -> String {
        (picked as NSString).pathExtension.lowercased() == ext ? picked : picked + ".\(ext)"
    }
    var allowsSeveralFiles: Bool { self == .notes }
}

/// A line the settings screens show after a save: the server's words, and whether it was a problem
struct SettingsNotice: Equatable {
    let text: String
    let isError: Bool
}
