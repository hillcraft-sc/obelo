import Foundation

// What GET /analytics returns: the same numbers as the web Analytics page (computeAnalytics on the server).
// Shared by the iPhone and iPad screen and the Mac screen.

struct Analytics: Decodable {
    struct Summary: Decodable {
        let total: Int
        let withDueCount: Int
        let trueOnTimeRate: Int?
        let sameDayRate: Int?
        let avgDaysLate: Double?
        let topDay: String?
        let topDayCount: Int
    }
    struct Streak: Decodable { let current: Int; let best: Int }
    struct Week: Decodable, Identifiable {
        let label: String
        let early: Int, on_time: Int, late_same_day: Int, late_1_3: Int, late_4_7: Int, late_8plus: Int
        var id: String { label }
        var total: Int { early + on_time + late_same_day + late_1_3 + late_4_7 + late_8plus }
        func count(_ bucket: String) -> Int {
            switch bucket {
            case "early": early
            case "on_time": on_time
            case "late_same_day": late_same_day
            case "late_1_3": late_1_3
            case "late_4_7": late_4_7
            default: late_8plus
            }
        }
    }
    struct RatePoint: Decodable, Identifiable { let label: String; let rate: Int?; let total: Int; var id: String { label } }
    struct CountPoint: Decodable, Identifiable { let label: String; let count: Int; var id: String { label } }
    struct LateAge: Decodable { let count: Int; let avg: Double; let median: Double; let max: Int }
    struct Priority: Decodable, Identifiable {
        let priority: String, label: String, total: Int
        let trueRate: Int?, sdRate: Int?
        var id: String { priority }
    }
    struct Heatmap: Decodable {
        struct Cell: Decodable, Hashable { let dateStr: String; let isFuture: Bool; let count: Int; let intensity: Int; let title: String }
        let weeks: [[Cell]]
        let dayLabels: [String]
        let weekLabels: [String]
    }
    struct RoutineStats: Decodable {
        struct Item: Decodable, Identifiable {
            struct Broken: Decodable { let length: Int; let endDate: String }
            let id: Int, title: String, frequency: String
            let specificTime: String?
            let expected: Int, completed: Int
            let rate: Int?
            let streakCurrent: Int, streakBest: Int, streakCount: Int, streakAvg: Int
            struct Top: Decodable { let length: Int; let startDate: String; let endDate: String; let isActive: Bool }
            let lastBroken: Broken?
            /// Its longest past streaks (the web lists them when there is more than one)
            let topStreaks: [Top]?
            let specificTimeRate: Int?
            let timedSampleSize: Int
        }
        let overallRate: Int?
        let totalExpected: Int
        let totalCompleted: Int
        let byRoutine: [Item]
    }
    struct RoutineWeek: Decodable, Identifiable { let label: String; let expected: Int; let completed: Int; let rate: Int?; var id: String { label } }

    let range: String
    let rangeLabel: String
    let summary: Summary
    let streak: Streak
    let weeklyData: [Week]
    let onTimeRateTrend: [RatePoint]
    let hasOnTimeRateTrend: Bool
    let todData: [CountPoint]
    let hasTodData: Bool
    let lateAgeStats: LateAge?
    let velocityData: [CountPoint]
    let velocityTrend: String
    let hasVelocityData: Bool
    let priorityData: [Priority]
    let heatmap: Heatmap
    let routineStats: RoutineStats
    let routineVelData: [RoutineWeek]
    let hasRoutineVelData: Bool
    /// "What stands out": a few findings from the user's data (nil from servers before 3.35)
    let standsOut: [Finding]?
    /// The findings were worded by AI (servers from 3.41)
    let standsOutByAi: Bool?

    struct Finding: Decodable, Hashable {
        /// warn, good or neutral
        let tone: String
        /// The web page behind the finding, e.g. /routines/5
        let href: String?
        let text: String

        /// Where the finding points: a module and, for one item, its id (the web page behind it is `href`)
        var target: (module: String, id: Int?)? {
            guard let href else { return nil }
            let parts = (href.split(separator: "?").first ?? "").split(separator: "/").map(String.init)
            guard let module = parts.first, ["tasks", "reminders", "routines", "notes"].contains(module) else { return nil }
            if parts.count == 1 { return (module, nil) }
            guard parts.count == 2, let id = Int(parts[1]) else { return nil }
            return (module, id)
        }
    }
}
