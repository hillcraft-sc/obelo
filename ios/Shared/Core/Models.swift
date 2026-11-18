import Foundation

// Shapes returned by /api/v1 (src/routes/api.js). Calendar days ("YYYY-MM-DD") and times
// ("HH:MM") stay strings, exactly as the server stores them, so no timezone conversion can
// shift a due date by a day.

struct Appearance: Codable, Equatable {
    var theme: String
    var isDark: Bool
    var customAccent: String
    var customBase: String
    var statusColors: String? = nil // "catppuccin" (default) or "tailwind"; only matters for Catppuccin themes
}

struct UserInfo: Codable, Equatable {
    let id: Int
    let username: String
    let displayName: String
    let email: String?
    let role: String
    let timezone: String
}

struct ModuleInfo: Codable, Equatable, Hashable {
    let key: String
    let label: String
    let beta: Bool
}

struct Me: Codable, Equatable {
    let user: UserInfo
    var appearance: Appearance
    let hour12: Bool
    var avatarUrl: String? = nil
    var hasCustomAvatar: Bool? = nil
    let modules: [ModuleInfo]
    let mobileNav: [String]
    let aiEnabled: Bool
    let canLockNotes: Bool
    let version: String?
    var notePaper: String? = nil // "theme" (default), "dark" or "white"; absent on a server without the setting
    /// The public demo: calendar accounts and notification channels are not available (the server refuses them)
    var demo: Bool? = nil
}

struct TaskItem: Codable, Identifiable, Equatable, Hashable {
    let id: Int
    var title: String
    var notes: String
    var status: String
    var priority: String
    var dueDate: String?
    var dueTime: String?
    var tags: [String]
    var recurring: Bool
    var recurRule: String?
    let parentId: Int?
    let createdAt: Date
    let updatedAt: Date
    let completedAt: Date?
    let dueState: String?
    var subtasks: [Subtask]?

    struct Subtask: Codable, Identifiable, Equatable, Hashable {
        let id: Int
        let title: String
        let done: Bool
    }

    var isDone: Bool { status == "done" }
}

struct ReminderItem: Codable, Identifiable, Equatable, Hashable {
    let id: Int
    var title: String
    var notes: String
    var dueDate: String?
    var dueTime: String?
    let reminderAt: Date?
    var priority: String
    var tags: [String]
    let completed: Bool
    var recurring: Bool
    var recurRule: String?
    let recurLabel: String
    let createdAt: Date
    let completedAt: Date?
    let dueState: String?
    var reminderOffset: Int?
}

struct Routine: Codable, Identifiable, Equatable, Hashable {
    let id: Int
    var title: String
    var description: String
    var timeOfDay: String
    var specificTime: String?
    var frequency: String
    var scheduleDays: [String]
    var durationDays: Int?
    var startDate: String?
    let streakCurrent: Int
    let streakBest: Int
    var tags: [String]
    var notify: Bool
    let active: Bool
    let completionCount: Int
    var completedToday: Bool
    let dueToday: Bool
    let finishedChallenge: Bool?
    /// Sent by server 3.49.0 and newer; nil from an older server
    var createdAt: Date? = nil
}

struct HeatmapDay: Codable, Hashable {
    let dateStr: String
    let isFuture: Bool
    let notApplicable: Bool
    let completed: Bool
    let label: String
}

struct WeeklyStat: Codable, Hashable {
    let label: String
    let completionCount: Int
    let dayCount: Int
    let rate: Int
}

struct NoteSummary: Codable, Identifiable, Equatable, Hashable {
    let id: Int
    let type: String
    let title: String
    let preview: String
    let tags: [String]
    let pinned: Bool
    let flaggedForReview: Bool
    let locked: Bool
    let hasDrawing: Bool
    let `private`: Bool
    /// nil = the top level (or a server older than 3.32, which has no folders)
    var folderId: Int? = nil
    let createdAt: Date
    let updatedAt: Date
}

struct Note: Codable, Identifiable, Equatable {
    let id: Int
    var type: String
    var title: String
    var preview: String
    var tags: [String]
    var pinned: Bool
    var flaggedForReview: Bool
    let locked: Bool
    let hasDrawing: Bool
    var `private`: Bool
    var folderId: Int? = nil
    let createdAt: Date
    var updatedAt: Date
    var content: String?
    var drawingData: String?
    var source: String?
    var author: String?
    var reviewDate: String?
    var attachments: [Attachment]
    var thoughts: [Thought]

    struct Attachment: Codable, Identifiable, Equatable {
        let id: Int
        let mimeType: String
        let url: String
    }

    struct Thought: Codable, Identifiable, Equatable {
        let id: Int
        let content: String
        let createdAt: Date
        let author: String
    }
}

struct ListSummary: Codable, Identifiable, Equatable, Hashable {
    let id: Int
    let title: String
    let createdAt: Date
    let isOwner: Bool
    let owner: String?
    let itemCount: Int
    let openCount: Int
}

struct ListDetail: Codable, Identifiable, Equatable {
    let id: Int
    var title: String
    let isOwner: Bool
    let owner: String?
    var items: [ListEntry]
    let sharedWith: [SharedUser]

    struct SharedUser: Codable, Equatable, Identifiable {
        let id: Int
        let username: String
        let displayName: String
    }
}

struct ListEntry: Codable, Identifiable, Equatable, Hashable {
    let id: Int
    var text: String
    var checked: Bool
    var position: Int
}

struct Bookmark: Codable, Identifiable, Equatable, Hashable {
    let id: Int
    var url: String
    var title: String?
    var description: String?
    var tags: [String]
    let createdAt: Date

    var host: String { URL(string: url)?.host() ?? url }
    var displayTitle: String { (title?.isEmpty == false ? title : nil) ?? host }
}

struct CalendarEvent: Codable, Identifiable, Equatable, Hashable {
    let id: Int
    let title: String
    let startAt: Date
    let endAt: Date
    let allDay: Bool
    let location: String?
    let description: String?
    let url: String?
    let calendarName: String?
    let color: String
    let day: String
    let editable: Bool
    let deletable: Bool
    let startTime: String?
    let endTime: String?
}

// ── Today ────────────────────────────────────────────────────────────────────

struct Dashboard: Codable, Equatable {
    struct Widget: Codable, Equatable {
        let key: String
        let enabled: Bool
    }

    struct DueEntry: Codable, Equatable, Identifiable {
        let type: String
        let overdue: Bool
        let task: TaskItem?
        let reminder: ReminderItem?
        var id: String { "\(type)-\(task?.id ?? reminder?.id ?? 0)" }
    }

    struct Resurfaced: Codable, Equatable {
        let id: Int
        let title: String
        let type: String
        let createdAt: Date
        let preview: String
    }

    struct ReviewNote: Codable, Equatable, Identifiable {
        let id: Int
        let title: String
        let reviewDate: String?
    }

    struct StaleNote: Codable, Equatable, Identifiable {
        let id: Int
        let title: String
        let daysAgo: Int
    }

    let widgets: [Widget]
    let slippingCount: Int
    var focusTasks: [TaskItem]
    let events: [CalendarEvent]
    var due: [DueEntry]
    var routines: [Routine]
    let resurfaced: Resurfaced?
    var review: [ReviewNote]
    let stale: [StaleNote]
}

// ── Capture ──────────────────────────────────────────────────────────────────

struct CaptureSuggestion: Codable, Equatable {
    var type: String
    var title: String?
    var content: String?
    var dueDate: String?
    var dueTime: String?
    var priority: String?
    var tags: [String]?
    var source: String?
    var author: String?
    var url: String?
    var items: [String]?
    var confidence: String?
}

struct CaptureDraft: Codable, Equatable {
    let draftId: Int
    var suggestion: CaptureSuggestion
}

// ── Search ───────────────────────────────────────────────────────────────────

struct SearchResponse: Codable {
    struct Group: Codable, Identifiable {
        let group: String
        let items: [Hit]
        var id: String { group }
    }

    struct Hit: Codable, Identifiable, Hashable {
        let type: String
        let id: Int
        let title: String
        let subtitle: String?
    }

    let results: [Group]
}

struct DeviceSession: Codable, Identifiable {
    let key: String
    let current: Bool
    let device: String
    let ip: String?
    let signedInAt: Date?
    let lastSeenAt: Date?
    var id: String { key }
}
