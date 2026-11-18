import Testing
@testable import ObeloShared

@MainActor
struct MarkdownViewTests {
    typealias B = MarkdownView.Block
    func blocks(_ text: String) -> [B] { MarkdownView.blocks(of: text) }

    @Test func headingsKeepTheirLevel() {
        #expect(blocks("# One\n## Two\n###### Six") == [.heading(1, "One"), .heading(2, "Two"), .heading(6, "Six")])
    }

    @Test func linesOfOneParagraphJoinAndABlankLineSplits() {
        #expect(blocks("first\nsecond\n\nthird") == [.paragraph("first\nsecond"), .paragraph("third")])
    }

    @Test func bulletsAndNumbersKeepTheirIndent() {
        let text = "- a\n  - b\n    - c\n1. one\n2) two"
        #expect(blocks(text) == [.bullet("a", indent: 0), .bullet("b", indent: 1), .bullet("c", indent: 2),
                                 .numbered("1", "one", indent: 0), .numbered("2", "two", indent: 0)])
    }

    @Test func checklistItemsKnowTheirStateAndTheirLine() {
        let text = "intro\n- [ ] open\n- [x] done\n  * [X] nested"
        #expect(blocks(text) == [.paragraph("intro"), .check(false, "open", indent: 0, line: 1),
                                 .check(true, "done", indent: 0, line: 2), .check(true, "nested", indent: 1, line: 3)])
    }

    @Test func aTextThatLooksLikeALineNumberIsCountedFromZeroOnTheWholeText() {
        let item = blocks("a\n\n- [ ] x").last
        #expect(item == .check(false, "x", indent: 0, line: 2))
    }

    @Test func consecutiveQuoteLinesBecomeOneQuote() {
        #expect(blocks("> one\n> two\n\nafter") == [.quote("one\ntwo"), .paragraph("after")])
    }

    @Test func codeFencesKeepEveryLineAsWritten() {
        let text = "before\n```swift\n# not a heading\n\n- not a bullet\n```\nafter"
        #expect(blocks(text) == [.paragraph("before"), .code("# not a heading\n\n- not a bullet"), .paragraph("after")])
    }

    @Test func anUnclosedFenceStillShowsItsCode() {
        #expect(blocks("```\nlet x = 1") == [.code("let x = 1")])
    }

    @Test func threeOrMoreDashesStarsOrUnderscoresMakeARule() {
        #expect(blocks("---\n***\n___") == [.rule, .rule, .rule])
    }

    @Test func windowsLineEndingsAreTreatedAsNewlines() {
        #expect(blocks("# T\r\n- a\r\n") == [.heading(1, "T"), .bullet("a", indent: 0)])
    }

    @Test func tickingAndUntickingKeepsTheRestOfTheLine() {
        let text = "x\n  - [ ] buy milk\n- [x] done"
        #expect(MarkdownView.toggling(text, line: 1, done: true) == "x\n  - [x] buy milk\n- [x] done")
        #expect(MarkdownView.toggling(text, line: 2, done: false) == "x\n  - [ ] buy milk\n- [ ] done")
    }

    @Test func tickingALineWithNoCheckboxChangesNothing() {
        #expect(MarkdownView.toggling("plain\n- bullet", line: 0, done: true) == nil)
        #expect(MarkdownView.toggling("plain\n- bullet", line: 1, done: true) == nil)
        #expect(MarkdownView.toggling("plain", line: 5, done: true) == nil)
    }
}
