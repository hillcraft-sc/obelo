import Foundation
import Testing
@testable import ObeloShared

func makeBookmark(_ id: Int, _ url: String = "https://example.com", title: String? = nil, description: String? = nil,
                  tags: [String] = [], age: TimeInterval = 0) -> Bookmark {
    Bookmark(id: id, url: url, title: title, description: description, tags: tags, createdAt: Date(timeIntervalSince1970: 1_800_000_000 - age))
}

@MainActor
final class StubBookmarksAPI: BookmarksAPI {
    struct Failure: LocalizedError { var errorDescription: String? { "Stub failure" } }
    var items: [Bookmark] = []
    var vocabulary: [String] = ["work", "read", "unused"]
    var people: [ListDetail.SharedUser] = [.init(id: 7, username: "sam", displayName: "Sam Lee"), .init(id: 8, username: "sasha", displayName: "Sasha")]
    var calls: [String] = []
    var failNext = false
    var nextId = 100

    private func record(_ s: String) throws { calls.append(s); if failNext { failNext = false; throw Failure() } }

    func list() async throws -> BookmarksResponse { try record("list"); return BookmarksResponse(bookmarks: items, tags: []) }
    func allTags() async throws -> [String] { try record("tags"); return vocabulary }
    func create(_ d: BookmarkDraft) async throws -> Bookmark {
        try record("create \(d.url)"); nextId += 1
        let b = makeBookmark(nextId, d.url, title: d.title.isEmpty ? nil : d.title, tags: d.tags)
        items.insert(b, at: 0)
        return b
    }
    func update(id: Int, _ d: BookmarkDraft) async throws {
        try record("update \(id) \(d.url)")
        if let i = items.firstIndex(where: { $0.id == id }) {
            items[i] = Bookmark(id: id, url: d.url, title: d.title.isEmpty ? nil : d.title, description: d.description.isEmpty ? nil : d.description, tags: d.tags, createdAt: items[i].createdAt)
        }
    }
    func delete(id: Int) async throws { try record("delete \(id)"); items.removeAll { $0.id == id } }
    func deleteMany(ids: [Int]) async throws -> Int {
        try record("deleteMany \(ids.sorted())")
        let before = items.count; items.removeAll { ids.contains($0.id) }; return before - items.count
    }
    func send(id: Int, username: String) async throws -> String {
        try record("send \(id) \(username)")
        guard people.contains(where: { $0.username == username }) else { throw Failure() }
        return "Sent to @\(username)"
    }
    func shareable() async throws -> [ListDetail.SharedUser] { try record("shareable"); return people }
}

@MainActor
struct BookmarksStoreTests {
    private func make(_ items: [Bookmark] = []) -> (BookmarksStore, StubBookmarksAPI) {
        let api = StubBookmarksAPI(); api.items = items
        return (BookmarksStore(api: api), api)
    }
    private let sample = [
        makeBookmark(1, "https://www.swift.org/docs", title: "Swift docs", description: "the language", tags: ["work", "read"], age: 300),
        makeBookmark(2, "https://zebra.example/a", title: "Zebra", tags: ["read"], age: 100),
        makeBookmark(3, "https://apple.com", tags: [], age: 200),
    ]

    @Test func loadsAndCollectsTags() async {
        let (s, _) = make(sample)
        await s.load()
        #expect(s.loaded && s.bookmarks.count == 3)
        #expect(s.tagList == ["read", "work"])
    }

    @Test func newestFirstByDefault() async {
        let (s, _) = make(sample)
        await s.load()
        #expect(s.visibleIDs == [2, 3, 1])
    }

    @Test func sortingByAHeadingAndAgain() async {
        let (s, _) = make(sample)
        await s.load()
        s.sort(by: .title)           // Swift docs, Zebra, apple.com's title is its site "apple.com"
        #expect(s.visibleIDs == [3, 1, 2])
        s.sort(by: .title)
        #expect(s.visibleIDs == [2, 1, 3])
        s.sort(by: .site)
        #expect(s.visibleIDs == [3, 1, 2])   // apple.com, swift.org (no www), zebra.example
        s.sort(by: .added)
        #expect(s.visibleIDs == [2, 3, 1])   // newest first the first time
        s.sort(by: .added)
        #expect(s.visibleIDs == [1, 3, 2])
    }

    @Test func siteDropsWww() {
        #expect(makeBookmark(1, "https://www.swift.org/docs").site == "swift.org")
    }

    @Test func onlyHttpAddressesAreLinks() {
        #expect(makeBookmark(1, "https://a.test").isWebLink)
        #expect(makeBookmark(2, "http://a.test").isWebLink)
        #expect(!makeBookmark(3, "javascript:alert(1)").isWebLink)
        #expect(!makeBookmark(4, "file:///etc/passwd").isWebLink)
    }

    @Test func searchMatchesTitleAddressNoteAndTags() async {
        let (s, _) = make(sample)
        await s.load()
        s.search = "ZEBRA"; #expect(s.visibleIDs == [2])
        s.search = "language"; #expect(s.visibleIDs == [1])
        s.search = "apple.com"; #expect(s.visibleIDs == [3])
        s.search = "work"; #expect(s.visibleIDs == [1])
        s.search = "nothing"; #expect(s.visible.isEmpty && s.isFiltered)
    }

    @Test func tagFilterAndClear() async {
        let (s, _) = make(sample)
        await s.load()
        s.toggleTag("read"); #expect(s.visibleIDs == [2, 1])
        s.search = "swift"; #expect(s.visibleIDs == [1])
        s.toggleTag("read"); #expect(s.activeTag == nil)
        s.toggleTag("work"); s.clearFilter()
        #expect(!s.isFiltered && s.visible.count == 3)
    }

    @Test func aTagThatNoLongerExistsClearsItsFilter() async {
        let (s, api) = make(sample)
        await s.load()
        s.toggleTag("work")
        api.items.removeAll { $0.id == 1 }
        await s.load()
        #expect(s.activeTag == nil)
    }

    @Test func addPutsItAtTheTop() async {
        let (s, api) = make(sample)
        await s.load()
        let b = await s.add(BookmarkDraft(url: "https://new.test", title: "New", tags: ["fresh"]))
        #expect(b != nil && s.bookmarks.first?.id == b?.id)
        #expect(s.tagList.contains("fresh"))
        #expect(api.calls.last == "create https://new.test")
    }

    @Test func addWithoutAnAddressIsRefusedWithoutAsking() async {
        let (s, api) = make()
        #expect(await s.add(BookmarkDraft(url: "  ")) == nil)
        #expect(s.error == "URL is required." && api.calls.isEmpty)
    }

    @Test func addFailureLeavesTheListAlone() async {
        let (s, api) = make(sample)
        await s.load(); api.failNext = true
        #expect(await s.add(BookmarkDraft(url: "https://x.test")) == nil)
        #expect(s.bookmarks.count == 3 && s.error == "Stub failure")
    }

    @Test func updateReloadsTheServersVersion() async {
        let (s, api) = make(sample)
        await s.load()
        #expect(await s.update(1, BookmarkDraft(url: "https://changed.test", title: "Changed", tags: ["x"])))
        #expect(s.bookmarks.first { $0.id == 1 }?.title == "Changed")
        #expect(s.tagList == ["read", "x"])
        #expect(api.calls.suffix(2) == ["update 1 https://changed.test", "list"])
    }

    @Test func updateErrors() async {
        let (s, api) = make(sample)
        await s.load()
        #expect(await !s.update(1, BookmarkDraft(url: "")) && s.error == "URL is required.")
        api.failNext = true; s.error = nil
        #expect(await !s.update(1, BookmarkDraft(url: "https://a.test")) && s.error == "Stub failure")
    }

    @Test func deleteOne() async {
        let (s, _) = make(sample)
        await s.load()
        s.click(2)
        await s.delete(2)
        #expect(s.bookmarks.map(\.id) == [1, 3] && s.selection.isEmpty)
    }

    @Test func deleteFailureKeepsTheRow() async {
        let (s, api) = make(sample)
        await s.load(); api.failNext = true
        await s.delete(2)
        #expect(s.bookmarks.count == 3 && s.error != nil)
    }

    @Test func deleteSelectedIsOneRequest() async {
        let (s, api) = make(sample)
        await s.load()
        s.click(2); s.click(1, command: true)
        #expect(s.selection.count == 2)
        #expect(await s.deleteSelected() == 2)
        #expect(s.bookmarks.map(\.id) == [3] && s.selection.isEmpty)
        #expect(api.calls.filter { $0.hasPrefix("delete") } == ["deleteMany [1, 2]"])
    }

    @Test func deleteSelectedFailureKeepsEverything() async {
        let (s, api) = make(sample)
        await s.load(); s.selectAll(); api.failNext = true
        #expect(await s.deleteSelected() == 0)
        #expect(s.bookmarks.count == 3 && s.selection.count == 3 && s.error != nil)
    }

    @Test func deleteSelectedWithNothingSelectedDoesNothing() async {
        let (s, api) = make(sample)
        await s.load()
        #expect(await s.deleteSelected() == 0)
        #expect(!api.calls.contains { $0.hasPrefix("delete") })
    }

    @Test func selectionFollowsTheFilter() async {
        let (s, _) = make(sample)
        await s.load()
        s.selectAll()
        s.toggleTag("work")           // only bookmark 1 is still shown
        #expect(s.selection.selected == [1])
    }

    @Test func shiftClickSelectsARunInTheShownOrder() async {
        let (s, _) = make(sample)
        await s.load()                // shown: 2, 3, 1
        s.click(2); s.click(1, shift: true)
        #expect(s.selection.selected == [1, 2, 3])
        s.arrow(1)
        #expect(s.selection.single != nil)
    }

    @Test func tagSuggestionsComeFromEverywhereOrFallBack() async {
        let (s, api) = make(sample)
        await s.load()
        await s.loadTagSuggestions()
        #expect(s.tagSuggestions == ["work", "read", "unused"])
        api.failNext = true
        await s.loadTagSuggestions()
        #expect(s.tagSuggestions == ["read", "work"])
    }

    @Test func sendingToAUser() async {
        let (s, api) = make(sample)
        #expect(await s.send(1, to: "sam") == "Sent to @sam")
        #expect(await s.send(1, to: "  ") == nil && s.error == "Username is required")
        #expect(await s.send(1, to: "nobody") == nil && s.error == "Stub failure")
        #expect(api.calls.filter { $0.hasPrefix("send") }.count == 2)
    }

    @Test func suggestionsAreEveryoneThenMatches() async {
        let (s, _) = make()
        await s.loadShareable()
        #expect(s.suggestions(for: "").count == 2)
        #expect(s.suggestions(for: "@sa").count == 2)
        #expect(s.suggestions(for: "lee").map(\.username) == ["sam"])
        #expect(s.suggestions(for: "zzz").isEmpty)
    }

    @Test func failedSuggestionsLoadSaysSoAndRetries() async {
        let (s, api) = make()
        api.failNext = true
        await s.loadShareable()
        #expect(s.error?.hasPrefix("Couldn't load the people") == true && s.shareable.isEmpty)
        await s.loadShareable()
        #expect(s.shareable.count == 2)
    }

    @Test func textForMessage() {
        #expect(BookmarksStore.textForMessage(makeBookmark(1, "https://a.test", title: "A")) == "A\nhttps://a.test")
        #expect(BookmarksStore.textForMessage(makeBookmark(2, "https://a.test", title: "https://a.test")) == "https://a.test")
    }

    @Test func loadFailureSetsTheError() async {
        let (s, api) = make(sample)
        api.failNext = true
        await s.load()
        #expect(s.error == "Stub failure" && !s.loaded)
    }
}
