import Foundation
import Testing
@testable import ObeloShared

func makeEvent(_ id: Int, _ title: String = "Event", day: String = "2026-11-14", start: String? = "09:00", end: String? = "10:00",
               allDay: Bool = false, editable: Bool = true, description: String? = nil, url: String? = nil, minute: Int = 0) -> CalendarEvent {
    CalendarEvent(id: id, title: title, startAt: Date(timeIntervalSince1970: 1_800_000_000 + Double(minute) * 60), endAt: Date(timeIntervalSince1970: 1_800_003_600),
                  allDay: allDay, location: nil, description: description, url: url, calendarName: "Work", color: "#112233", day: day,
                  editable: editable, deletable: editable, startTime: allDay ? nil : start, endTime: allDay ? nil : end)
}

@MainActor
final class StubCalendarAPI: CalendarAPI {
    struct Failure: LocalizedError { var errorDescription: String? { "Stub failure" } }
    var all: [CalendarEvent] = []
    var sources: [CalendarSourceInfo]? = []
    var calendars = [CalendarChoice(value: "local", label: "Local only", color: "#374151"), CalendarChoice(value: "1|caldav|x", label: "Work", color: "#112233")]
    var defaultTarget = "local"
    var calls: [String] = []
    var failNext = false
    var nextId = 100

    private func record(_ s: String) throws { calls.append(s); if failNext { failNext = false; throw Failure() } }

    func events(from: String, days: Int) async throws -> CalendarResponse {
        try record("events \(from) \(days)")
        let to = CalendarMath.addDays(from, days)
        return CalendarResponse(from: from, days: days, today: "2026-11-14", events: all.filter { $0.day >= from && $0.day < to }, sources: sources)
    }
    func choices() async throws -> CalendarChoices { try record("choices"); return CalendarChoices(calendars: calendars, defaultTarget: defaultTarget) }
    func create(_ d: EventDraft) async throws {
        try record("create \(d.title) \(d.date) \(d.calendarTarget)"); nextId += 1
        all.append(makeEvent(nextId, d.title, day: d.date, start: d.startTime, end: d.endTime, allDay: d.allDay))
    }
    func update(id: Int, _ d: EventDraft) async throws {
        try record("update \(id) \(d.title) \(d.date)")
        if let i = all.firstIndex(where: { $0.id == id }) { all[i] = makeEvent(id, d.title, day: d.date, start: d.startTime, end: d.endTime, allDay: d.allDay) }
    }
    func delete(id: Int) async throws { try record("delete \(id)"); all.removeAll { $0.id == id } }
}

@MainActor
struct CalendarStoreTests {
    private func make(_ events: [CalendarEvent] = []) -> (CalendarStore, StubCalendarAPI) {
        let api = StubCalendarAPI(); api.all = events
        return (CalendarStore(api: api, today: "2026-11-14"), api)
    }

    // ── Dates ──
    @Test func mondayFirstWeeks() {
        #expect(CalendarMath.monday(of: "2026-11-14") == "2026-11-09")   // a Saturday
        #expect(CalendarMath.monday(of: "2026-11-09") == "2026-11-09")
        #expect(CalendarMath.monday(of: "2026-11-15") == "2026-11-09")   // a Sunday belongs to the week before
        #expect(CalendarMath.weekdayIndex("2026-11-16") == 0)
    }

    @Test func monthMath() {
        #expect(CalendarMath.addMonths("2026-11-01", 1) == "2026-12-01")
        #expect(CalendarMath.addMonths("2026-01-01", -1) == "2025-12-01")
        #expect(CalendarMath.daysInMonth("2027-02-10") == 28)
        #expect(CalendarMath.addDays("2026-12-30", 3) == "2027-01-02")
    }

    @Test func weekRangeAndLabel() {
        let (s, _) = make()
        #expect(s.rangeStart == "2026-11-09" && s.rangeEnd == "2026-11-15" && s.dayCount == 7)
        #expect(s.rangeLabel == "Nov 9 – Nov 15, 2026")
        #expect(s.days(inWeek: 0).first == "2026-11-09" && s.days(inWeek: 0).last == "2026-11-15")
    }

    @Test func weekLabelAcrossAYear() async {
        let api = StubCalendarAPI()
        let s = CalendarStore(api: api, today: "2026-12-31")
        #expect(s.rangeLabel == "Dec 28 – Jan 3, 2027")
    }

    @Test func monthRangeHasAsManyWeeksAsItNeeds() async {
        let (s, _) = make()
        await s.setMode(.month)
        #expect(s.rangeLabel == "November 2026")
        #expect(s.rangeStart == "2026-10-26" && s.weekCount == 6 && s.dayCount == 42)   // Nov 1 is a Sunday
        await s.show(day: "2027-02-10")
        #expect(s.rangeStart == "2027-02-01" && s.weekCount == 4)                        // Feb 1 is a Monday, 28 days
        await s.show(day: "2026-12-05")
        #expect(s.rangeStart == "2026-11-30" && s.weekCount == 5)
    }

    @Test func fadedDaysAreOutsideTheMonth() async {
        let (s, _) = make()
        await s.setMode(.month)
        #expect(s.isInMonth("2026-11-14") && !s.isInMonth("2026-10-30") && !s.isInMonth("2026-12-01"))
    }

    // ── Loading and moving ──
    @Test func loadAsksForTheWholeRange() async {
        let (s, api) = make([makeEvent(1)])
        await s.load()
        #expect(api.calls == ["events 2026-11-09 7"] && s.events.count == 1 && s.loaded)
        await s.setMode(.month)
        #expect(api.calls.last == "events 2026-10-26 42")
    }

    @Test func previousNextAndToday() async {
        let (s, api) = make()
        await s.next();     #expect(s.rangeStart == "2026-11-16" && api.calls.last == "events 2026-11-16 7")
        await s.previous(); await s.previous()
        #expect(s.rangeStart == "2026-11-02")
        await s.goToToday(); #expect(s.rangeStart == "2026-11-09")
    }

    @Test func monthNavigationGoesByMonths() async {
        let (s, _) = make()
        await s.setMode(.month)
        await s.next();     #expect(s.rangeLabel == "December 2026")
        await s.previous(); await s.previous(); #expect(s.rangeLabel == "October 2026")
        await s.goToToday(); #expect(s.rangeLabel == "November 2026")
    }

    @Test func changingViewKeepsTheDay() async {
        let (s, _) = make()
        await s.show(day: "2026-12-24")
        await s.setMode(.month); await s.setMode(.week)
        #expect(s.rangeStart == "2026-12-21")
    }

    @Test func eventsByDayEarliestFirst() async {
        let (s, _) = make([makeEvent(1, "Late", minute: 600), makeEvent(2, "Early", minute: 5), makeEvent(3, "Other day", day: "2026-11-10")])
        await s.load()
        #expect(s.events(on: "2026-11-14").map(\.title) == ["Early", "Late"])
        #expect(s.events(on: "2026-11-11").isEmpty)
    }

    @Test func loadFailureSetsTheError() async {
        let (s, api) = make()
        api.failNext = true
        await s.load()
        #expect(s.error == "Stub failure" && !s.loaded)
    }

    // ── Connected calendars ──
    @Test func noticeOnlyWhenTheServerSaidThereAreNone() async {
        let (s, api) = make()
        await s.load()
        #expect(s.showsNoCalendarsNotice)
        api.sources = [CalendarSourceInfo(name: "Work", color: "#1", lastSynced: nil)]
        await s.load()
        #expect(!s.showsNoCalendarsNotice && s.sources.count == 1)
    }

    @Test func anOlderServerShowsNeitherNoticeNorLegend() async {
        let (s, api) = make()
        api.sources = nil
        await s.load()
        #expect(!s.showsNoCalendarsNotice && s.sources.isEmpty)
    }

    // ── The open event ──
    @Test func selectingAndLosingTheSelection() async {
        let (s, api) = make([makeEvent(1), makeEvent(2, "Elsewhere", day: "2026-11-20")])
        await s.load()
        s.select(1); #expect(s.selected?.id == 1)
        api.all.removeAll { $0.id == 1 }
        await s.load()
        #expect(s.selectedID == nil)
    }

    @Test func openingAnEventFromAnotherWeekGoesThere() async {
        let far = makeEvent(7, "Far", day: "2026-12-24")
        let (s, _) = make([far])
        await s.open(far)
        #expect(s.rangeStart == "2026-12-21" && s.selectedID == 7 && s.selected?.title == "Far")
    }

    // ── Add, edit, delete ──
    @Test func choicesLoadOnce() async {
        let (s, api) = make()
        await s.loadChoices(); await s.loadChoices()
        #expect(s.choices.count == 2 && s.defaultTarget == "local")
        #expect(api.calls.filter { $0 == "choices" }.count == 1)
    }

    @Test func choicesFailureSaysSoAndRetries() async {
        let (s, api) = make()
        api.failNext = true
        await s.loadChoices()
        #expect(s.error?.hasPrefix("Couldn't load your calendars") == true && s.choices.isEmpty)
        await s.loadChoices()
        #expect(s.choices.count == 2)
    }

    @Test func draftChecksSayWhatTheServerSays() {
        var d = EventDraft(date: "2026-11-14")
        #expect(CalendarStore.problem(with: d) == "Title is required.")
        d.title = "Lunch"; d.date = ""
        #expect(CalendarStore.problem(with: d) == "Date is required.")
        d.date = "2026-11-14"; d.startTime = "10:00"; d.endTime = "09:00"
        #expect(CalendarStore.problem(with: d) == "The event ends before it starts.")
        d.allDay = true
        #expect(CalendarStore.problem(with: d) == nil)
    }

    @Test func addingSelectsTheNewEvent() async {
        let (s, api) = make()
        await s.load()
        var d = EventDraft(date: "2026-11-12"); d.title = "  Dentist  "
        let made = await s.add(d)
        #expect(made?.title == "Dentist" && s.selectedID == made?.id)
        #expect(api.calls.contains("create Dentist 2026-11-12 local"))
    }

    @Test func addingOnAnotherWeekMovesThere() async {
        let (s, _) = make()
        await s.load()
        var d = EventDraft(date: "2027-01-05"); d.title = "New year"
        let made = await s.add(d)
        #expect(s.rangeStart == "2027-01-04" && made != nil)
    }

    @Test func addingWithAProblemDoesNotAsk() async {
        let (s, api) = make()
        #expect(await s.add(EventDraft(date: "2026-11-14")) == nil)
        #expect(s.error == "Title is required." && api.calls.isEmpty)
    }

    @Test func addFailureKeepsWhatWasThere() async {
        let (s, api) = make([makeEvent(1)])
        await s.load(); api.failNext = true
        var d = EventDraft(date: "2026-11-14"); d.title = "X"
        #expect(await s.add(d) == nil)
        #expect(s.events.count == 1 && s.error == "Stub failure")
    }

    @Test func editingFollowsTheDateToAnotherWeek() async {
        let (s, _) = make([makeEvent(1, "Old")])
        await s.load(); s.select(1)
        var d = EventDraft(s.selected!); d.title = "New"; d.date = "2026-12-03"
        #expect(await s.update(1, d))
        #expect(s.rangeStart == "2026-11-30" && s.selected?.title == "New")
    }

    @Test func editingErrors() async {
        let (s, api) = make([makeEvent(1)])
        await s.load()
        var d = EventDraft(s.events[0]); d.title = ""
        #expect(await !s.update(1, d) && s.error == "Title is required.")
        d.title = "Ok"; api.failNext = true; s.error = nil
        #expect(await !s.update(1, d) && s.error == "Stub failure")
    }

    @Test func deleting() async {
        let (s, _) = make([makeEvent(1), makeEvent(2, "Keep", minute: 30)])
        await s.load(); s.select(1)
        await s.delete(1)
        #expect(s.events.map(\.id) == [2] && s.selectedID == nil)
    }

    @Test func deleteFailureKeepsTheEvent() async {
        let (s, api) = make([makeEvent(1)])
        await s.load(); api.failNext = true
        await s.delete(1)
        #expect(s.events.count == 1 && s.error != nil)
    }

    // ── Text ──
    @Test func draftFromAnEventDropsTheOldMarker() {
        let e = makeEvent(1, "Imported", description: "[vT] Bring slides")
        #expect(EventDraft(e).description == "Bring slides")
        #expect(CalendarStore.cleanNotes(nil) == "" && CalendarStore.cleanNotes("Plain") == "Plain")
    }

    @Test func timeText() {
        #expect(CalendarStore.timeText(makeEvent(1, start: "09:00", end: "13:30"), hour12: true) == "9:00 AM – 1:30 PM")
        #expect(CalendarStore.timeText(makeEvent(1, start: "09:00", end: "13:30"), hour12: false) == "09:00 – 13:30")
        #expect(CalendarStore.timeText(makeEvent(2, allDay: true), hour12: true) == "All day")
    }

    @Test func longDate() {
        #expect(CalendarStore.longDate("2026-11-14") == "Saturday, November 14, 2026")
    }

    @Test func onlyWebLinksOpen() {
        #expect(CalendarStore.isWebLink("https://meet.test/x") && CalendarStore.isWebLink("http://a.test"))
        #expect(!CalendarStore.isWebLink("javascript:alert(1)") && !CalendarStore.isWebLink(nil) && !CalendarStore.isWebLink("webcal://x"))
    }
}
