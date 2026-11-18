import Foundation

/// Turns pointer input into strokes (the Mac canvas feeds it mouse, trackpad and pen events). The rules
/// are the web canvas's and the iPhone's: points less than 2pt apart are dropped, at most 500 strokes,
/// pressure 0.1 to 1 (0.5 without a pen), the canvas grows by 800pt when you draw within 300pt of the
/// bottom, and a drawing made at another width is scaled to this one.
struct DrawingRecorder: Equatable {
    var doc: DrawingDoc
    var color = DrawingRenderer.colors[0]
    var width: Double = 3
    var erasing = false
    private(set) var current: DrawingDoc.Stroke?

    init(doc: DrawingDoc = DrawingDoc(w: 0, h: DrawingDoc.defaultHeight, strokes: [])) { self.doc = doc }

    static func pressure(_ raw: Double?) -> Double { min(1, max(0.1, raw ?? 0.5)) }

    mutating func begin(x: Double, y: Double, pressure: Double? = nil) {
        current = DrawingDoc.Stroke(color: color, width: erasing ? DrawingRenderer.eraserWidth : width, eraser: erasing,
                                    points: [.init(x: x, y: y, p: Self.pressure(pressure))])
    }

    /// Adds a point to the stroke being drawn. Returns true when the canvas needs to grow.
    @discardableResult
    mutating func add(x: Double, y: Double, pressure: Double? = nil) -> Bool {
        guard current != nil else { return false }
        if let last = current?.points.last, (x - last.x) * (x - last.x) + (y - last.y) * (y - last.y) < 4 { return false }
        current?.points.append(.init(x: x, y: y, p: Self.pressure(pressure)))
        return growIfNeeded(forY: y)
    }

    /// Finishes the stroke. Returns true when it was kept (not over the stroke limit).
    @discardableResult
    mutating func end() -> Bool {
        guard let stroke = current else { return false }
        current = nil
        guard doc.strokes.count < DrawingDoc.maxStrokes else { return false }
        doc.strokes.append(stroke)
        return true
    }

    mutating func cancel() { current = nil }

    /// Removes the last stroke. Returns false when there is nothing to undo.
    @discardableResult
    mutating func undo() -> Bool {
        guard !doc.strokes.isEmpty else { return false }
        doc.strokes.removeLast()
        return true
    }

    mutating func clear() { doc.strokes = []; current = nil }

    @discardableResult
    mutating func growIfNeeded(forY y: Double) -> Bool {
        let height = max(doc.h, DrawingDoc.defaultHeight)
        guard y > height - 300 else { return false }
        doc.h = height + 800
        return true
    }

    /// Scales a drawing made at another width to `width` (the first layout, and when the window is resized)
    mutating func adopt(width: Double) {
        guard width > 0 else { return }
        if doc.w == 0 { doc.w = width; return }
        doc = doc.scaled(toWidth: width)
    }
}
