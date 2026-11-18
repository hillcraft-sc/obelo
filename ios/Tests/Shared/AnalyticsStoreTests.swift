import Foundation
import Testing
@testable import ObeloShared

/// A full response, with the parts a test cares about changeable
func makeAnalytics(total: Int = 20, weeks: [[Int]] = [[3, 5, 1, 1, 0, 0]], velocityTrend: String = "steady",
                   standsOut: String = "[]", routines: String = "[]", rangeLabel: String = "Last 30 days") -> Analytics {
    let weekJSON = weeks.enumerated().map { i, w in
        "{\"label\":\"W\(i)\",\"early\":\(w[0]),\"on_time\":\(w[1]),\"late_same_day\":\(w[2]),\"late_1_3\":\(w[3]),\"late_4_7\":\(w[4]),\"late_8plus\":\(w[5])}"
    }.joined(separator: ",")
    let json = """
    {"range":"30","rangeLabel":"\(rangeLabel)",
     "summary":{"total":\(total),"withDueCount":10,"trueOnTimeRate":80,"sameDayRate":null,"avgDaysLate":2.5,"topDay":"Tuesday","topDayCount":4},
     "streak":{"current":3,"best":9},
     "weeklyData":[\(weekJSON)],
     "onTimeRateTrend":[{"label":"W0","rate":75,"total":8},{"label":"W1","rate":null,"total":0}],"hasOnTimeRateTrend":true,
     "todData":[{"label":"9am","count":4}],"hasTodData":true,
     "lateAgeStats":null,
     "velocityData":[{"label":"W0","count":4}],"velocityTrend":"\(velocityTrend)","hasVelocityData":true,
     "priorityData":[{"priority":"high","label":"High","total":4,"trueRate":50,"sdRate":75},{"priority":"low","label":"Low","total":0,"trueRate":null,"sdRate":null}],
     "heatmap":{"weeks":[[{"dateStr":"2026-11-02","isFuture":false,"count":2,"intensity":2,"title":"Nov 2: 2"}]],"dayLabels":["M"],"weekLabels":["Nov 2"]},
     "routineStats":{"overallRate":70,"totalExpected":10,"totalCompleted":7,"byRoutine":\(routines)},
     "routineVelData":[],"hasRoutineVelData":false,
     "standsOut":\(standsOut),"standsOutByAi":true}
    """
    return try! JSONDecoder().decode(Analytics.self, from: Data(json.utf8))
}

@MainActor
final class StubAnalyticsAPI: AnalyticsAPI {
    struct Failure: LocalizedError { var errorDescription: String? { "Stub failure" } }
    var result = makeAnalytics()
    var calls: [String] = []
    var failNext = false
    func load(range: String) async throws -> Analytics {
        calls.append(range)
        if failNext { failNext = false; throw Failure() }
        return result
    }
}

@MainActor
struct AnalyticsStoreTests {
    private func make(_ a: Analytics = makeAnalytics()) -> (AnalyticsStore, StubAnalyticsAPI) {
        let api = StubAnalyticsAPI(); api.result = a
        UserDefaults.standard.removeObject(forKey: "analyticsRange")
        return (AnalyticsStore(api: api), api)
    }

    @Test func loadsTheNumbersAndStartsAtThirtyDays() async {
        let (s, api) = make()
        #expect(!s.loaded)
        await s.load()
        #expect(s.loaded && s.data?.summary.total == 20 && s.error == nil)
        #expect(api.calls == ["30"])
    }

    @Test func changingTheRangeAsksAgainAndIsRemembered() async {
        let (s, api) = make()
        await s.load()
        await s.setRange(.all)
        #expect(api.calls == ["30", "all"])
        #expect(s.range == .all)
        #expect(UserDefaults.standard.string(forKey: "analyticsRange") == "all")
        await s.setRange(.all)
        #expect(api.calls.count == 2, "choosing the same range again asks nothing")
        let again = AnalyticsStore(api: api)
        #expect(again.range == .all)
        UserDefaults.standard.removeObject(forKey: "analyticsRange")
    }

    @Test func aFailedLoadKeepsWhatWasOnScreen() async {
        let (s, api) = make()
        await s.load()
        api.failNext = true
        await s.setRange(.days90)
        #expect(s.error == "Stub failure")
        #expect(s.data?.summary.total == 20)
        await s.load()
        #expect(s.error == nil)
    }

    @Test func rateBandsFollowTheWebsThresholds() {
        #expect(RateBand(nil) == .none)
        #expect(RateBand(80) == .good && RateBand(100) == .good)
        #expect(RateBand(79) == .fair && RateBand(50) == .fair)
        #expect(RateBand(49) == .low && RateBand(0) == .low)
    }

    @Test func smallSampleNoticeIsForOneToFourCompletions() async {
        for (n, shows) in [(0, false), (1, true), (4, true), (5, false)] {
            let (s, _) = make(makeAnalytics(total: n)); await s.load()
            #expect(s.showsSmallSampleNotice == shows, "total \(n)")
        }
        let (s, _) = make(makeAnalytics(total: 1)); await s.load()
        #expect(s.smallSampleText == "Analytics improve with more data — you have 1 completion in this period. Percentages are based on a small sample.")
    }

    @Test func timingSentenceMatchesTheWeb() async {
        func say(_ w: [[Int]]) async -> String? { let (s, _) = make(makeAnalytics(weeks: w)); await s.load(); return s.timingNarrative }
        #expect(await say([[0, 0, 0, 0, 0, 0]]) == nil)
        #expect(await say([[1, 0, 0, 0, 0, 0]]) == "Your one completion was on time or early this period.")
        #expect(await say([[1, 1, 0, 0, 0, 0]]) == "Both completions were on time or early this period.")
        #expect(await say([[2, 1, 0, 0, 0, 0]]) == "All 3 completions were on time or early this period.")
        #expect(await say([[0, 0, 3, 0, 0, 0]]) == "All 3 completions were same-day late — you hit the right day but missed the due time by more than 30 minutes.")
        #expect(await say([[0, 0, 0, 1, 1, 1]]) == "All 3 completions were finished days after the due date.")
        // 3 early + 5 on time + 1 same-day + 1 late = 10: 80% on time, one item days late
        #expect(await say([[3, 5, 1, 1, 0, 0]]) == "80% of completions were on time or early (8 of 10). 1 item was days late.")
        #expect(await say([[0, 1, 4, 0, 1, 0]]) == "67% of completions were same-day late — right day, but past the due time. 1 item was days late.")
        #expect(await say([[1, 0, 0, 2, 2, 0]]) == "80% of completions were finished days after their due date (4 of 5). 1 item was on time or early.")
    }

    @Test func timingSentenceAddsUpAllWeeks() async {
        let (s, _) = make(makeAnalytics(weeks: [[1, 0, 0, 0, 0, 0], [0, 1, 0, 0, 0, 0]]))
        await s.load()
        #expect(s.hasTimingData)
        #expect(s.timingNarrative == "Both completions were on time or early this period.")
    }

    @Test func velocityWording() async {
        for (trend, label, band) in [("up", "↑ trending up", RateBand.good), ("down", "↓ trending down", .low), ("steady", "→ steady", .none)] {
            let (s, _) = make(makeAnalytics(velocityTrend: trend)); await s.load()
            #expect(s.velocityLabel == label && s.velocityBand == band)
        }
    }

    @Test func prioritiesWithNoItemsAreLeftOut() async {
        let (s, _) = make(); await s.load()
        #expect(s.priorities.map(\.priority) == ["high"])
    }

    @Test func findingsPointAtTheItemBehindThem() async {
        let found = "[{\"tone\":\"warn\",\"href\":\"/routines/5\",\"text\":\"a\"},{\"tone\":\"good\",\"href\":\"/tasks?view=overdue\",\"text\":\"b\"},{\"tone\":\"neutral\",\"href\":null,\"text\":\"c\"},{\"tone\":\"neutral\",\"href\":\"/settings\",\"text\":\"d\"},{\"tone\":\"warn\",\"href\":\"/notes/9\",\"text\":\"e\"}]"
        let (s, _) = make(makeAnalytics(standsOut: found)); await s.load()
        let t = s.findings.map { $0.target }
        #expect(t[0]?.module == "routines" && t[0]?.id == 5)
        #expect(t[1]?.module == "tasks" && t[1]?.id == nil)
        #expect(t[2] == nil && t[3] == nil)
        #expect(t[4]?.module == "notes" && t[4]?.id == 9)
        #expect(s.findingsByAI)
    }

    @Test func noFindingsWhenTheServerSendsNone() async {
        let (s, _) = make(); await s.load()
        #expect(s.findings.isEmpty)
        #expect(AnalyticsStore(api: StubAnalyticsAPI()).findings.isEmpty)
    }

    private func routine(current: Int = 0, best: Int = 0, count: Int = 0, avg: Int = 0, broken: String = "null",
                         time: String = "null", timeRate: String = "null", sample: Int = 0, top: String = "[]") -> Analytics.RoutineStats.Item {
        let a = makeAnalytics(routines: """
        [{"id":1,"title":"Run","frequency":"daily","specificTime":\(time),"expected":10,"completed":7,"rate":70,
          "streakCurrent":\(current),"streakBest":\(best),"streakCount":\(count),"streakAvg":\(avg),"lastBroken":\(broken),
          "specificTimeRate":\(timeRate),"timedSampleSize":\(sample),"topStreaks":\(top)}]
        """)
        return a.routineStats.byRoutine[0]
    }

    @Test func routineLinesAreAsTheWebs() {
        let live = AnalyticsStore.notes(for: routine(current: 4, best: 9, count: 3, avg: 5))
        #expect(live.map(\.text) == ["🔥 4d streak · best 9d", "3 streaks · avg 5d"])
        let atBest = AnalyticsStore.notes(for: routine(current: 9, best: 9, count: 1, avg: 9))
        #expect(atBest.map(\.text) == ["🔥 9d streak", "1 streak · avg 9d"])
        let broke = AnalyticsStore.notes(for: routine(best: 6, count: 2, avg: 4, broken: "{\"length\":6,\"endDate\":\"2026-11-03T00:00:00.000Z\"}"))
        #expect(broke.map(\.text) == ["best 6d", "2 streaks · avg 4d", "broke 6d · Nov 3"])
        let timed = AnalyticsStore.notes(for: routine(time: "\"07:30\"", timeRate: "40", sample: 3))
        #expect(timed.map(\.text) == ["on time at 07:30: 40% (3 logged)"])
        let timedMany = AnalyticsStore.notes(for: routine(time: "\"07:30\"", timeRate: "90", sample: 12))
        #expect(timedMany.map(\.text) == ["on time at 07:30: 90%"])
        #expect(AnalyticsStore.notes(for: routine()).isEmpty)
    }

    @Test func topStreaksShowOnlyWhenThereIsMoreThanOne() {
        let one = routine(top: "[{\"length\":5,\"startDate\":\"2026-10-01\",\"endDate\":\"2026-10-05\",\"isActive\":false}]")
        #expect(AnalyticsStore.topStreakText(one) == nil)
        let two = routine(top: "[{\"length\":9,\"startDate\":\"2026-10-01\",\"endDate\":\"2026-10-09\",\"isActive\":true},{\"length\":5,\"startDate\":\"2026-09-02\",\"endDate\":\"2026-09-06\",\"isActive\":false}]")
        #expect(AnalyticsStore.topStreakText(two) == "9d (Oct 1–Oct 9 ▶) · 5d (Sep 2–Sep 6)")
        #expect(AnalyticsStore.topStreakText(routine()) == nil)
    }

    @Test func smallWording() {
        #expect(AnalyticsStore.plural(1, "item") == "1 item" && AnalyticsStore.plural(2, "item") == "2 items")
        #expect(AnalyticsStore.frequencyLabel("weekdays") == "Weekdays" && AnalyticsStore.frequencyLabel("odd") == "odd")
        #expect(AnalyticsStore.shortDate("2026-12-25T00:00:00.000Z") == "Dec 25")
        #expect(AnalyticsStore.shortDate("nonsense") == "nonsense")
    }
}
