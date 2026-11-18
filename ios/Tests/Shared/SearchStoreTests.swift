import Foundation
import Testing
@testable import ObeloShared

@MainActor
final class StubSearchAPI: SearchAPI {
    struct Failure: LocalizedError { var errorDescription: String? { "down" } }
    var groups: [SearchResponse.Group] = []
    var calls: [String] = []
    var failNext = false
    func search(_ query: String) async throws -> [SearchResponse.Group] {
        calls.append(query)
        if failNext { failNext = false; throw Failure() }
        return groups
    }
    func event(id: Int) async throws -> CalendarEvent { throw Failure() }
}

func hit(_ type: String, _ id: Int, _ title: String, _ sub: String? = nil) -> SearchResponse.Hit {
    SearchResponse.Hit(type: type, id: id, title: title, subtitle: sub)
}

@MainActor
struct SearchStoreTests {
    private let sample = [
        SearchResponse.Group(group: "Notes", items: [hit("note", 1, "Trip plan"), hit("note", 2, "Trip budget")]),
        SearchResponse.Group(group: "Tasks", items: [hit("task", 9, "Book the trip", "due 2026-12-01")]),
    ]

    private func make(_ groups: [SearchResponse.Group]? = nil) -> (SearchStore, StubSearchAPI) {
        let api = StubSearchAPI(); api.groups = groups ?? sample
        return (SearchStore(api: api, delay: .milliseconds(5)), api)
    }

    @Test func startsWithTheHint() {
        let (s, _) = make()
        #expect(s.phase == .hint && s.message == "Type at least 2 characters to search")
    }

    @Test func oneCharacterAsksNothing() async {
        let (s, api) = make()
        s.query = "t"
        await s.settle()
        #expect(api.calls.isEmpty && s.phase == .hint)
    }

    @Test func twoCharactersSearchAfterAPause() async {
        let (s, api) = make()
        s.query = "tr"
        #expect(s.phase == .searching && s.message == "Searching…")
        await s.settle()
        #expect(api.calls == ["tr"] && s.phase == .results && s.message == nil)
        #expect(s.hits.map(\.id) == [1, 2, 9])
        #expect(s.highlighted == 0 && s.current?.title == "Trip plan")
    }

    @Test func quickTypingMakesOneSearch() async {
        let (s, api) = make()
        s.query = "tr"; s.query = "tri"; s.query = "trip"
        await s.settle()
        #expect(api.calls == ["trip"])
    }

    @Test func spacesAroundTheTextDontCount() async {
        let (s, api) = make()
        s.query = "  t "
        await s.settle()
        #expect(api.calls.isEmpty && s.phase == .hint)
        s.query = "  trip "
        await s.settle()
        #expect(api.calls == ["trip"])
    }

    @Test func noMatchesSaysSo() async {
        let (s, _) = make([])
        s.query = "zzz"
        await s.settle()
        #expect(s.phase == .empty && s.message == "No results for \"zzz\"")
    }

    @Test func aFailedSearchSaysSo() async {
        let (s, api) = make()
        api.failNext = true
        s.query = "trip"
        await s.settle()
        #expect(s.phase == .failed && s.message == "Search failed — please try again." && s.hits.isEmpty)
        s.query = "trips"
        await s.settle()
        #expect(s.phase == .results)
    }

    @Test func oldRowsStayWhileTheNextSearchRuns() async {
        let (s, _) = make()
        s.query = "trip"; await s.settle()
        s.query = "trips"
        #expect(s.phase == .searching && s.hits.count == 3 && s.message == nil)
        await s.settle()
    }

    @Test func backToOneCharacterShowsTheHintAgain() async {
        let (s, _) = make()
        s.query = "trip"; await s.settle()
        s.query = "t"
        #expect(s.phase == .hint && s.hits.isEmpty)
    }

    @Test func arrowsStopAtTheEnds() async {
        let (s, _) = make()
        s.query = "trip"; await s.settle()
        s.move(-1)
        #expect(s.highlighted == 0)
        s.move(1); s.move(1); s.move(1); s.move(1)
        #expect(s.highlighted == 2 && s.current?.id == 9)
        s.move(-1)
        #expect(s.highlighted == 1)
    }

    @Test func newResultsHighlightTheFirstRow() async {
        let (s, _) = make()
        s.query = "trip"; await s.settle()
        s.move(1)
        s.query = "trips"; await s.settle()
        #expect(s.highlighted == 0)
    }

    @Test func hoveringACanMoveTheHighlight() async {
        let (s, _) = make()
        s.query = "trip"; await s.settle()
        s.highlight(hit("task", 9, "Book the trip", "due 2026-12-01"))
        #expect(s.highlighted == 2)
    }

    @Test func resetForgetsEverything() async {
        let (s, _) = make()
        s.query = "trip"; await s.settle()
        s.reset()
        #expect(s.query.isEmpty && s.hits.isEmpty && s.phase == .hint && s.highlighted == 0)
    }

    @Test func highlightPiecesIgnoreCase() {
        let p = SearchStore.pieces(of: "Book the TRIP, a trip", matching: "trip")
        #expect(p.map(\.text) == ["Book the ", "TRIP", ", a ", "trip"])
        #expect(p.map(\.isMatch) == [false, true, false, true])
        #expect(SearchStore.pieces(of: "Nothing", matching: "zz") == [HighlightPiece(text: "Nothing", isMatch: false)])
        #expect(SearchStore.pieces(of: "", matching: "a").isEmpty)
        #expect(SearchStore.pieces(of: "Café", matching: "cafe").map(\.isMatch) == [true])
    }

    @Test func kindsHaveIconsAndWords() {
        #expect(SearchStore.icon(for: "calendar") == "calendar" && SearchStore.icon(for: "x") == "circle")
        #expect(SearchStore.spokenKind("calendar") == "Event" && SearchStore.spokenKind("bookmark") == "Bookmark")
    }
}
