import Testing
@testable import ObeloShared

@MainActor
struct RowSelectionTests {
    let rows = [1, 2, 3, 4, 5]

    @Test func plainClickSelectsOneAndReplaces() {
        var s = RowSelection<Int>()
        s.click(2, in: rows)
        s.click(4, in: rows)
        #expect(s.selected == [4])
        #expect(s.single == 4)
    }

    @Test func commandClickTogglesAndKeepsOthers() {
        var s = RowSelection<Int>()
        s.click(1, in: rows)
        s.click(3, in: rows, command: true)
        #expect(s.selected == [1, 3])
        #expect(s.single == nil)
        s.click(1, in: rows, command: true)
        #expect(s.selected == [3])
    }

    @Test func shiftClickSelectsTheRunFromTheAnchorEitherWay() {
        var s = RowSelection<Int>()
        s.click(2, in: rows)
        s.click(4, in: rows, shift: true)
        #expect(s.selected == [2, 3, 4])
        s.click(1, in: rows, shift: true)           // anchor stays on 2
        #expect(s.selected == [1, 2])
    }

    @Test func commandShiftAddsTheRun() {
        var s = RowSelection<Int>()
        s.click(1, in: rows)
        s.click(4, in: rows, command: true)
        s.click(5, in: rows, command: true, shift: true) // anchor 4, run 4...5
        #expect(s.selected == [1, 4, 5])
    }

    @Test func shiftClickWithNoAnchorActsLikeAPlainClick() {
        var s = RowSelection<Int>()
        s.click(3, in: rows, shift: true)
        #expect(s.selected == [3])
    }

    @Test func arrowKeysMoveAndStayInTheList() {
        var s = RowSelection<Int>()
        s.step(1, in: rows)
        #expect(s.selected == [1])
        s.step(1, in: rows)
        s.step(1, in: rows)
        #expect(s.selected == [3])
        s.step(-10, in: rows)
        #expect(s.selected == [1])
        s.step(99, in: rows)
        #expect(s.selected == [5])
    }

    @Test func arrowUpWithNothingSelectedStartsAtTheLastRow() {
        var s = RowSelection<Int>()
        s.step(-1, in: rows)
        #expect(s.selected == [5])
    }

    @Test func arrowKeysOnAnEmptyListDoNothing() {
        var s = RowSelection<Int>()
        s.step(1, in: [])
        #expect(s.isEmpty)
    }

    @Test func pruneDropsRowsThatLeftTheList() {
        var s = RowSelection<Int>()
        s.selectAll(in: rows)
        s.prune(to: [2, 3])
        #expect(s.selected == [2, 3])
        #expect(s.anchor == nil || [2, 3].contains(s.anchor!))
        s.clear()
        #expect(s.isEmpty && s.anchor == nil)
    }

    @Test func setReplacesTheSelectionAndKeepsALiveAnchor() {
        var s = RowSelection<Int>()
        s.click(2, in: rows)
        s.set([2, 3])
        #expect(s.selected == [2, 3] && s.anchor == 2)
        s.set([4])
        #expect(s.selected == [4] && s.anchor == 4)
    }
}
