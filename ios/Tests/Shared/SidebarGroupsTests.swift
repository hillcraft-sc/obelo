import Testing
@testable import ObeloShared

struct SidebarGroupsTests {
    private let all = ["dashboard", "capture", "notes", "tasks", "lists", "reminders", "routines", "calendar", "bookmarks", "analytics", "ai", "settings"]

    @Test func groupsAreInThePlansOrderWhateverTheSavedOrder() {
        let g = SidebarGroups.groups(enabled: all)
        #expect(g.map(\.title) == [nil, "Do", "Write", "Plan", "See", "Assist"])
        #expect(g[0].keys == ["dashboard", "capture"])
        #expect(g[1].keys == ["tasks", "reminders", "routines"])
        #expect(g[2].keys == ["notes", "lists", "bookmarks"])
    }

    @Test func aReorderedSavedListChangesNothing() {
        let shuffled = ["lists", "notes", "tasks", "routines", "reminders", "capture", "bookmarks", "ai", "dashboard", "calendar", "analytics"]
        #expect(SidebarGroups.groups(enabled: shuffled) == SidebarGroups.groups(enabled: all))
    }

    @Test func switchedOffModulesAndEmptyGroupsDisappear() {
        let g = SidebarGroups.groups(enabled: ["dashboard", "tasks", "notes", "bookmarks"])
        #expect(g.map(\.title) == [nil, "Do", "Write"])
        #expect(g[0].keys == ["dashboard"] && g[1].keys == ["tasks"] && g[2].keys == ["notes", "bookmarks"])
    }

    @Test func settingsIsNeverInTheListAndAnUnplacedModuleGetsAMoreGroup() {
        let g = SidebarGroups.groups(enabled: ["dashboard", "settings", "journal"])
        #expect(g.flatMap(\.keys) == ["dashboard", "journal"])
        #expect(g.last?.title == "More")
    }

    @Test func orderIsTheSidebarTopToBottom() {
        #expect(SidebarGroups.order(enabled: all) == ["dashboard", "capture", "tasks", "reminders", "routines", "notes", "lists", "bookmarks", "calendar", "analytics", "ai"])
    }

    @Test func listingModulesInTheSidebarsOrder() {
        let keys = ["settings", "lists", "journal", "tasks", "dashboard", "notes"]
        #expect(keys.sorted { SidebarGroups.sortRank($0) < SidebarGroups.sortRank($1) } == ["dashboard", "tasks", "notes", "lists", "journal", "settings"])
    }
}
