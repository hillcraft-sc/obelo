import Testing
import Foundation
@testable import ObeloShared

@Suite struct DrawingRecorderTests {
    private func recorder() -> DrawingRecorder { var r = DrawingRecorder(); r.adopt(width: 600); return r }

    @Test func aStrokeIsKeptWithThePensColourAndWidth() {
        var r = recorder()
        r.color = "#93c5fd"; r.width = 6
        r.begin(x: 10, y: 10)
        r.add(x: 50, y: 40)
        let kept = r.end()
        #expect(kept)
        #expect(r.doc.strokes.count == 1)
        #expect(r.doc.strokes[0].color == "#93c5fd")
        #expect(r.doc.strokes[0].width == 6)
        #expect(r.doc.strokes[0].eraser == false)
        #expect(r.doc.strokes[0].points.map(\.p) == [0.5, 0.5])
    }

    @Test func theEraserDrawsWithItsOwnWidth() {
        var r = recorder()
        r.erasing = true; r.width = 1.5
        r.begin(x: 10, y: 10); r.add(x: 80, y: 80); r.end()
        #expect(r.doc.strokes[0].eraser == true)
        #expect(r.doc.strokes[0].width == DrawingRenderer.eraserWidth)
    }

    @Test func pointsLessThanTwoPointsApartAreDropped() {
        var r = recorder()
        r.begin(x: 10, y: 10)
        r.add(x: 11, y: 10)      // 1pt away
        r.add(x: 11, y: 11)      // still under 2pt from the first
        r.add(x: 20, y: 10)
        r.end()
        #expect(r.doc.strokes[0].points.count == 2)
    }

    @Test func pressureStaysBetweenTenAndOneHundredPercent() {
        #expect(DrawingRecorder.pressure(nil) == 0.5)
        #expect(DrawingRecorder.pressure(0) == 0.1)
        #expect(DrawingRecorder.pressure(3) == 1)
        #expect(DrawingRecorder.pressure(0.7) == 0.7)
    }

    @Test func atMostFiveHundredStrokes() {
        var r = recorder()
        for i in 0..<(DrawingDoc.maxStrokes + 5) {
            r.begin(x: 10, y: 10 + Double(i % 5)); r.add(x: 90, y: 10)
            _ = r.end()
        }
        #expect(r.doc.strokes.count == DrawingDoc.maxStrokes)
    }

    @Test func undoRemovesTheLastStrokeAndClearEmptiesTheDrawing() {
        var r = recorder()
        for x in [10.0, 40, 70] { r.begin(x: x, y: 10); r.add(x: x + 20, y: 50); r.end() }
        let undone = r.undo()
        #expect(undone)
        #expect(r.doc.strokes.count == 2)
        r.clear()
        #expect(r.doc.strokes.isEmpty)
        let again = r.undo()
        #expect(!again)
    }

    @Test func theCanvasGrowsWhenYouDrawNearTheBottom() {
        var r = recorder()
        r.begin(x: 10, y: 100)
        let early = r.add(x: 20, y: 600)
        #expect(!early)
        let grew = r.add(x: 30, y: DrawingDoc.defaultHeight - 100)
        #expect(grew)
        #expect(r.doc.h == DrawingDoc.defaultHeight + 800)
        let again = r.add(x: 40, y: DrawingDoc.defaultHeight - 100)   // now there is room again
        #expect(!again)
    }

    @Test func aDrawingMadeAtAnotherWidthIsScaled() {
        var r = DrawingRecorder(doc: DrawingDoc(w: 300, h: 1200, strokes: [
            .init(color: "#f1f5f9", width: 3, eraser: false, points: [.init(x: 30, y: 60, p: 0.5), .init(x: 90, y: 120, p: 0.5)])]))
        r.adopt(width: 600)
        #expect(r.doc.w == 600)
        #expect(r.doc.strokes[0].points[1].x == 180)
        #expect(r.doc.strokes[0].points[1].y == 240)
    }

    @Test func aBlankDrawingTakesTheCanvasWidthAsItIs() {
        var r = DrawingRecorder()
        r.adopt(width: 640)
        #expect(r.doc.w == 640)
        #expect(r.doc.strokes.isEmpty)
    }

    @Test func aCancelledStrokeLeavesNothing() {
        var r = recorder()
        r.begin(x: 10, y: 10); r.add(x: 50, y: 50); r.cancel()
        #expect(r.current == nil)
        let kept = r.end()
        #expect(!kept)
        #expect(r.doc.strokes.isEmpty)
    }
}
