import Foundation
import Testing
@testable import ObeloShared

func makeListSummary(_ id: Int, _ title: String = "List", total: Int = 0, open: Int = 0, owner: Bool = true) -> ListSummary {
    ListSummary(id: id, title: title, createdAt: Date(), isOwner: owner, owner: owner ? nil : "Sam", itemCount: total, openCount: open)
}

/// A fake server: lists and items in memory, a log of calls, and a switch to make the next call fail
@MainActor
final class StubListsAPI: ListsAPI {
    struct Failure: LocalizedError { var errorDescription: String? { "Stub failure" } }
    var mine: [ListDetail] = []
    var shared: [ListDetail] = []
    var people: [ListDetail.SharedUser] = [.init(id: 7, username: "sam", displayName: "Sam Lee"), .init(id: 8, username: "sasha", displayName: "Sasha")]
    var calls: [String] = []
    var failNext = false
    var nextId = 100

    private func record(_ s: String) throws { calls.append(s); if failNext { failNext = false; throw Failure() } }
    private func summary(_ d: ListDetail) -> ListSummary {
        ListSummary(id: d.id, title: d.title, createdAt: Date(), isOwner: d.isOwner, owner: d.owner,
                    itemCount: d.items.count, openCount: d.items.filter { !$0.checked }.count)
    }
    private func idx(_ id: Int) -> Int? { mine.firstIndex { $0.id == id } }

    func lists() async throws -> ListsResponse { try record("lists"); return ListsResponse(lists: mine.map(summary), shared: shared.map(summary)) }
    func detail(id: Int) async throws -> ListDetail {
        try record("detail \(id)")
        guard let d = (mine + shared).first(where: { $0.id == id }) else { throw Failure() }
        return d
    }
    func create(title: String) async throws -> ListSummary {
        try record("create \(title)"); nextId += 1
        let d = ListDetail(id: nextId, title: title, isOwner: true, owner: nil, items: [], sharedWith: [])
        mine.insert(d, at: 0)
        return summary(d)
    }
    func rename(id: Int, title: String) async throws {
        try record("rename \(id) \(title)")
        if let i = idx(id) { let d = mine[i]; mine[i] = ListDetail(id: id, title: title, isOwner: true, owner: nil, items: d.items, sharedWith: d.sharedWith) }
    }
    func delete(id: Int) async throws { try record("delete \(id)"); mine.removeAll { $0.id == id } }
    func addItem(listID: Int, text: String) async throws -> ListEntry {
        try record("add \(listID) \(text)"); nextId += 1
        let e = ListEntry(id: nextId, text: text, checked: false, position: mine[idx(listID)!].items.count)
        mine[idx(listID)!].items.append(e)
        return e
    }
    func toggle(listID: Int, itemID: Int) async throws -> Bool {
        try record("toggle \(itemID)")
        let i = mine[idx(listID)!].items.firstIndex { $0.id == itemID }!
        mine[idx(listID)!].items[i].checked.toggle()
        return mine[idx(listID)!].items[i].checked
    }
    func editItem(listID: Int, itemID: Int, text: String) async throws {
        try record("edit \(itemID) \(text)")
        let i = mine[idx(listID)!].items.firstIndex { $0.id == itemID }!
        mine[idx(listID)!].items[i].text = text
    }
    func deleteItem(listID: Int, itemID: Int) async throws { try record("deleteItem \(itemID)"); mine[idx(listID)!].items.removeAll { $0.id == itemID } }
    func reorder(listID: Int, ids: [Int]) async throws { try record("reorder \(ids)") }
    func share(listID: Int, username: String) async throws {
        try record("share \(username)")
        guard let p = people.first(where: { $0.username == username }) else { throw Failure() }
        let d = mine[idx(listID)!]
        mine[idx(listID)!] = ListDetail(id: d.id, title: d.title, isOwner: true, owner: nil, items: d.items, sharedWith: d.sharedWith + [p])
    }
    func unshare(listID: Int, userID: Int) async throws { try record("unshare \(userID)") }
    func shareable() async throws -> [ListDetail.SharedUser] { try record("shareable"); return people }
}

@MainActor
struct ListsStoreTests {
    func make() async -> (ListsStore, StubListsAPI) {
        let api = StubListsAPI()
        api.mine = [
            ListDetail(id: 1, title: "Groceries", isOwner: true, owner: nil, items: [
                ListEntry(id: 11, text: "Milk", checked: false, position: 0), ListEntry(id: 12, text: "Eggs", checked: false, position: 1),
                ListEntry(id: 13, text: "Bread", checked: true, position: 2), ListEntry(id: 14, text: "Jam", checked: false, position: 3),
            ], sharedWith: []),
            ListDetail(id: 2, title: "Packing", isOwner: true, owner: nil, items: [], sharedWith: []),
        ]
        api.shared = [ListDetail(id: 3, title: "Trip", isOwner: false, owner: "Sam", items: [ListEntry(id: 31, text: "Tent", checked: false, position: 0)], sharedWith: [])]
        let s = ListsStore(api: api)
        await s.load()
        return (s, api)
    }

    @Test func loadsMineAndSharedWithTheirCounts() async {
        let (s, _) = await make()
        #expect(s.mine.map(\.id) == [1, 2])
        #expect(s.shared.map(\.id) == [3])
        #expect(s.showsMineHeading)
        #expect(ListsStore.counts(s.mine[0]) == "3 active · 1 done")
        #expect(ListsStore.counts(s.mine[1]) == "0 active")
    }

    @Test func theMyListsHeadingShowsOnlyWhenSomethingIsShared() async {
        let (s, api) = await make()
        api.shared = []
        await s.load()
        #expect(!s.showsMineHeading)
    }

    @Test func openingAListShowsOpenItemsFirstAndDoneBelow() async {
        let (s, _) = await make()
        await s.select(1)
        #expect(s.activeItems.map(\.text) == ["Milk", "Eggs", "Jam"])
        #expect(s.doneItems.map(\.text) == ["Bread"])
    }

    @Test func createTrimsOpensTheNewListAndRefusesAnEmptyName() async {
        let (s, api) = await make()
        #expect(await s.create(title: "   ") == nil)
        #expect(s.error == "Title is required.")
        #expect(!api.calls.contains { $0.hasPrefix("create") })
        let l = await s.create(title: "  Tools ")
        #expect(l?.title == "Tools")
        #expect(s.mine.first?.id == l?.id)
        #expect(s.selectedID == l?.id)
        #expect(s.open?.title == "Tools")
    }

    @Test func renameChangesTheRowAndThePaneAndIgnoresAnEmptyTitle() async {
        let (s, api) = await make()
        await s.select(1)
        #expect(await s.rename(1, to: "  Shopping ") )
        #expect(api.calls.last == "rename 1 Shopping")
        #expect(s.mine[0].title == "Shopping")
        #expect(s.open?.title == "Shopping")
        #expect(await s.rename(1, to: "  ") == false)
        #expect(api.calls.last == "rename 1 Shopping")
    }

    @Test func aFailedRenameKeepsTheOldTitleAndShowsTheError() async {
        let (s, api) = await make()
        api.failNext = true
        #expect(await s.rename(1, to: "X") == false)
        #expect(s.mine[0].title == "Groceries")
        #expect(s.error == "Stub failure")
    }

    @Test func deletingTheOpenListClosesIt() async {
        let (s, _) = await make()
        await s.select(2)
        await s.delete(2)
        #expect(s.mine.map(\.id) == [1])
        #expect(s.selectedID == nil && s.open == nil)
    }

    @Test func addingAnItemPutsItLastAndCountsIt() async {
        let (s, _) = await make()
        await s.select(1)
        #expect(await s.addItem("  Tea  "))
        #expect(s.activeItems.last?.text == "Tea")
        #expect(s.mine[0].openCount == 4 && s.mine[0].itemCount == 5)
        #expect(await s.addItem("  ") == false)
    }

    @Test func tickingMovesTheItemToDoneAtOnceAndUpdatesTheCounts() async {
        let (s, _) = await make()
        await s.select(1)
        await s.toggle(11)
        #expect(s.doneItems.map(\.id).contains(11))
        #expect(s.mine[0].openCount == 2)
        await s.toggle(13)
        #expect(s.activeItems.map(\.id).contains(13))
        #expect(s.mine[0].openCount == 3)
    }

    @Test func aFailedTickPutsTheRowBack() async {
        let (s, api) = await make()
        await s.select(1)
        api.failNext = true
        await s.toggle(11)
        #expect(s.activeItems.map(\.id).contains(11))
        #expect(s.mine[0].openCount == 3)
        #expect(s.error != nil)
    }

    @Test func editingAnItemTrimsAndAFailureRestoresTheText() async {
        let (s, api) = await make()
        await s.select(1)
        #expect(await s.editItem(11, text: " Oat milk "))
        #expect(s.activeItems[0].text == "Oat milk")
        api.failNext = true
        #expect(await s.editItem(11, text: "Soy") == false)
        #expect(s.activeItems[0].text == "Oat milk")
        #expect(await s.editItem(11, text: " ") == false)
    }

    @Test func deletingAnItemUpdatesTheCounts() async {
        let (s, _) = await make()
        await s.select(1)
        await s.deleteItem(13)   // a done one
        #expect(s.mine[0].itemCount == 3 && s.mine[0].openCount == 3)
        await s.deleteItem(11)   // an open one
        #expect(s.mine[0].itemCount == 2 && s.mine[0].openCount == 2)
    }

    @Test func reorderingSendsTheOpenItemsInTheirNewOrderOnce() async {
        let (s, api) = await make()
        await s.select(1)
        await s.moveActive(from: 2, to: 0)   // Jam to the top
        #expect(s.activeItems.map(\.text) == ["Jam", "Milk", "Eggs"])
        #expect(api.calls.last == "reorder [14, 11, 12]")
        #expect(s.doneItems.map(\.text) == ["Bread"])
    }

    @Test func movingDownUsesTheSwiftUIDestination() async {
        let (s, api) = await make()
        await s.select(1)
        await s.moveActive(from: 0, to: 2)   // Milk after Eggs
        #expect(s.activeItems.map(\.text) == ["Eggs", "Milk", "Jam"])
        #expect(api.calls.last == "reorder [12, 11, 14]")
    }

    @Test func aMoveThatChangesNothingSendsNothing() async {
        let (s, api) = await make()
        await s.select(1)
        let n = api.calls.count
        await s.moveActive(from: 1, to: 1)
        await s.moveActive(from: 1, to: 2)
        #expect(api.calls.count == n)
    }

    @Test func aFailedReorderPutsTheOrderBack() async {
        let (s, api) = await make()
        await s.select(1)
        api.failNext = true
        await s.moveActive(from: 2, to: 0)
        #expect(s.activeItems.map(\.text) == ["Milk", "Eggs", "Jam"])
        #expect(s.error != nil)
    }

    @Test func nudgeMovesOneStepAndStopsAtTheEnds() async {
        let (s, _) = await make()
        await s.select(1)
        await s.nudge(12, by: -1)
        #expect(s.activeItems.map(\.text) == ["Eggs", "Milk", "Jam"])
        await s.nudge(12, by: -1)   // already first
        #expect(s.activeItems.map(\.text) == ["Eggs", "Milk", "Jam"])
        await s.nudge(14, by: 1)    // already last
        #expect(s.activeItems.map(\.text) == ["Eggs", "Milk", "Jam"])
        await s.nudge(12, by: 1)
        #expect(s.activeItems.map(\.text) == ["Milk", "Eggs", "Jam"])
    }

    @Test func suggestionsMatchUsernameOrNameAndSkipPeopleAlreadySharedWith() async {
        let (s, _) = await make()
        await s.select(1)
        await s.loadShareable()
        #expect(s.suggestions(for: "sa").map(\.username) == ["sam", "sasha"])
        #expect(s.suggestions(for: "@lee").map(\.username) == ["sam"])
        #expect(s.suggestions(for: "zzz").isEmpty)
        await s.share(username: "sam")
        #expect(s.open?.sharedWith.map(\.username) == ["sam"])
        #expect(s.suggestions(for: "sa").map(\.username) == ["sasha"])
    }

    @Test func everyoneIsSuggestedBeforeAnythingIsTyped() async {
        let (s, _) = await make()
        await s.select(1)
        await s.loadShareable()
        #expect(s.suggestions(for: "").map(\.username) == ["sam", "sasha"])
        #expect(s.suggestions(for: "  ").map(\.username) == ["sam", "sasha"])
    }

    @Test func ifThePeopleCantBeLoadedItSaysSoAndTriesAgainNextTime() async {
        let (s, api) = await make()
        await s.select(1)
        api.failNext = true
        await s.loadShareable()
        #expect(s.error?.hasPrefix("Couldn't load the people you can share with.") == true)
        #expect(s.suggestions(for: "").isEmpty)
        await s.loadShareable()
        #expect(s.suggestions(for: "").count == 2)
    }

    @Test func aRefusedShareShowsTheErrorAndKeepsTheList() async {
        let (s, _) = await make()
        await s.select(1)
        #expect(await s.share(username: "nobody") == false)
        #expect(s.error == "Stub failure")
        #expect(s.open?.sharedWith.isEmpty == true)
    }

    @Test func unsharingTakesThePersonOffAtOnce() async {
        let (s, api) = await make()
        await s.select(1)
        await s.share(username: "sam")
        await s.unshare(7)
        #expect(api.calls.last == "unshare 7")
        #expect(s.open?.sharedWith.isEmpty == true)
    }

    @Test func theTextForMessagesListsOpenThenDone() async {
        let (s, _) = await make()
        #expect(s.textForMessage == nil)
        await s.select(1)
        #expect(s.textForMessage == "Groceries\n\n• Milk\n• Eggs\n• Jam\n✓ Bread")
        await s.select(2)
        #expect(s.textForMessage == "Packing\n\n(no items)")
    }

    @Test func aLoadFailureShowsTheErrorAndKeepsWhatWasThere() async {
        let (s, api) = await make()
        api.failNext = true
        await s.load()
        #expect(s.error == "Stub failure")
        #expect(s.mine.count == 2)
    }

    @Test func aListThatDisappearsFromTheServerIsClosed() async {
        let (s, api) = await make()
        await s.select(2)
        api.mine.removeAll { $0.id == 2 }
        await s.load()
        #expect(s.selectedID == nil && s.open == nil)
    }
}
