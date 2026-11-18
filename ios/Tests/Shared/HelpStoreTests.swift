import Foundation
import Testing
@testable import ObeloShared

@MainActor
final class StubHelpAPI: HelpAPI {
    struct Failure: LocalizedError { var errorDescription: String? { "down" } }
    var content: HelpContent
    var failNext = false
    var calls = 0
    init(_ c: HelpContent) { content = c }
    func help() async throws -> HelpContent {
        calls += 1
        if failNext { failNext = false; throw Failure() }
        return content
    }
}

func helpContent(_ ids: [String] = ["capture", "tasks", "search", "mobile"]) -> HelpContent {
    let sections = ids.map { HelpContent.Section(id: $0, title: $0.capitalized) }
    let html = ids.map { "<section id=\"\($0)\"><div><h2>\($0.capitalized)</h2><p>Text of \($0)</p></div></section>" }.joined()
    return HelpContent(sections: sections, html: html)
}

@MainActor
struct HelpStoreTests {
    private let groups = [ShortcutGroup(title: "Navigation", rows: [.init(label: "Search", keys: "⌘K"), .init(label: "A & B", keys: "<x>")])]

    private func make(_ c: HelpContent = helpContent()) -> (HelpStore, StubHelpAPI) {
        let api = StubHelpAPI(c); return (HelpStore(api: api), api)
    }

    @Test func loadsAndStartsAtTheFirstSection() async {
        let (s, _) = make()
        #expect(!s.loaded && s.sections.isEmpty)
        await s.load()
        #expect(s.loaded && s.current == "capture" && s.error == nil)
    }

    @Test func theMobileSectionIsLeftOutAndShortcutsComeAfterSearch() async {
        let (s, _) = make()
        await s.load()
        #expect(s.sections.map(\.id) == ["capture", "tasks", "search", "shortcuts"])
        #expect(s.sections.last?.title == "Keyboard Shortcuts")
    }

    @Test func theServersOwnShortcutsSectionIsReplaced() async {
        let (s, _) = make(helpContent(["capture", "search", "shortcuts", "mobile"]))
        await s.load()
        #expect(s.sections.map(\.id) == ["capture", "search", "shortcuts"])
        let page = s.html(shortcuts: groups)
        #expect(page.components(separatedBy: "id=\"shortcuts\"").count == 2, "exactly one shortcuts card")
        #expect(!page.contains("Text of shortcuts"))
    }

    @Test func thePageLosesMobileAndGainsTheMacShortcutsAfterSearch() async {
        let (s, _) = make()
        await s.load()
        let page = s.html(shortcuts: groups)
        #expect(!page.contains("id=\"mobile\"") && !page.contains("Text of mobile"))
        let search = page.range(of: "id=\"search\"")!.lowerBound
        let shortcuts = page.range(of: "id=\"shortcuts\"")!.lowerBound
        #expect(search < shortcuts)
        #expect(page.contains("Text of capture") && page.contains("Text of tasks"))
    }

    @Test func shortcutsAreEscaped() {
        let h = HelpStore.shortcutsHTML(groups)
        #expect(h.contains("A &amp; B") && h.contains("&lt;x&gt;") && !h.contains("<x>"))
        #expect(h.contains("<h3>Navigation</h3>") && h.contains("⌘K"))
    }

    @Test func withoutASearchSectionShortcutsGoLast() {
        let page = HelpStore.page(from: "<section id=\"capture\"><div>a</div></section>", shortcuts: groups)
        #expect(page.hasSuffix("</section>") && page.contains("id=\"shortcuts\""))
        #expect(page.range(of: "id=\"capture\"")!.lowerBound < page.range(of: "id=\"shortcuts\"")!.lowerBound)
    }

    @Test func selectingASectionMarksItAndAsksForAScroll() async {
        let (s, _) = make()
        await s.load()
        s.select("tasks")
        #expect(s.current == "tasks" && s.jump == "tasks")
    }

    @Test func aFailedLoadSaysWhyAndCanBeRetried() async {
        let (s, api) = make()
        api.failNext = true
        await s.load()
        #expect(!s.loaded && s.error == "down")
        await s.load()
        #expect(s.loaded && s.error == nil && api.calls == 2)
    }

    @Test func linksGoToTheRightPlace() {
        #expect(HelpLink.classify(URL(string: "#tasks")!) == .section("tasks"))
        #expect(HelpLink.classify(URL(string: "about:blank#calendar")!) == .section("calendar"))
        #expect(HelpLink.classify(URL(string: "https://appleid.apple.com")!) == .web(URL(string: "https://appleid.apple.com")!))
        #expect(HelpLink.classify(URL(string: "javascript:alert(1)")!) == .ignore)
        #expect(HelpLink.classify(URL(string: "obelo://auth?code=1")!) == .ignore)
        #expect(HelpLink.classify(URL(string: "/tasks")!) == .ignore)
    }

    @Test func findAsksOnlyWithWords() {
        let (s, _) = make()
        s.find()
        #expect(s.findRequest == 0)
        s.findQuery = "streak"
        s.find()
        #expect(s.findRequest == 1 && !s.findBackwards)
        s.find(backwards: true)
        #expect(s.findRequest == 2 && s.findBackwards)
    }
}
