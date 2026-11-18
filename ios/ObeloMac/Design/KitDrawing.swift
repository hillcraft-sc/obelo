import AppKit
import SwiftUI

// Handwriting: the pen colours, the drawing toolbar and the canvas (web: notes/_editor.ejs, the Draw panel).
// The stroke rules (2pt spacing, 500 strokes, growth, scaling) are `DrawingRecorder` in Shared, with tests;
// the canvas only turns Mac mouse, trackpad and pen events into calls on it.

/// The four pen colours as round swatches. They show the shade you get on the paper in use, and the
/// selected one has a ring (none while the eraser is on).
struct KitPenSwatches: View {
    @Environment(\.theme) private var theme
    @Binding var color: String
    let erasing: Bool
    let paper: DrawingPaper

    private static let names = ["#f1f5f9": "Main ink", "#93c5fd": "Blue", "#fca5a5": "Red", "#86efac": "Green"]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(DrawingRenderer.colors, id: \.self) { c in
                Button { color = c } label: {
                    Circle().fill(Color(hex: paper.ink(c))).frame(width: 20, height: 20)
                        .overlay(Circle().strokeBorder(theme.border3, lineWidth: 1))
                        .overlay(Circle().strokeBorder(theme.accent, lineWidth: !erasing && color == c ? 2 : 0).padding(-4))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(Self.names[c] ?? c)
                .accessibilityLabel(Self.names[c] ?? c)
                .accessibilityAddTraits(!erasing && color == c ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(.horizontal, 4)
    }
}

/// Pen colours, S / M / L, Eraser, Undo, Clear, in a tray like the formatting toolbar
struct KitDrawingToolbar: View {
    @Environment(\.theme) private var theme
    @Binding var color: String
    @Binding var width: Double
    @Binding var erasing: Bool
    let paper: DrawingPaper
    let canUndo: Bool
    let undo: () -> Void
    let clear: () -> Void

    var body: some View {
        KitFlowLayout(spacing: 10) {
            KitPenSwatches(color: $color, erasing: erasing, paper: paper)
            divider
            KitPillSelector(options: DrawingRenderer.sizes.map { (value: $0.1, label: $0.0) }, selection: $width, label: "Pen size")
            divider
            Button { erasing.toggle() } label: { Label("Eraser", systemImage: "eraser") }
                .buttonStyle(KitButtonStyle(erasing ? .primary : .secondary, small: true))
                .help("Eraser")
            divider
            Button(action: undo) { Label("Undo", systemImage: "arrow.uturn.backward") }
                .buttonStyle(KitButtonStyle(.secondary, small: true))
                .help("Undo the last stroke (⌘Z)")
                .disabled(!canUndo)
            Button(action: clear) { Label("Clear", systemImage: "xmark") }
                .buttonStyle(KitButtonStyle(.secondary, small: true))
                .help("Clear the whole drawing")
                .disabled(!canUndo)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(theme.elevated, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Drawing tools")
    }

    private var divider: some View {
        Rectangle().fill(theme.border3).frame(width: 1, height: 16).frame(height: 26)
    }
}

/// Lets the toolbar's Undo reach the canvas
@MainActor
final class KitDrawingController {
    fileprivate weak var canvas: KitDrawingNSView?
    func undo() { canvas?.undoStroke() }
}

/// The drawing area: ruled paper, scrolls, grows as you draw near the bottom. Click and drag to draw
/// (a pen tablet adds pressure). ⌘Z undoes the last stroke while the canvas has the focus.
struct KitDrawingCanvas: NSViewRepresentable {
    @Binding var doc: DrawingDoc
    let color: String
    let width: Double
    let erasing: Bool
    let paper: DrawingPaper
    let controller: KitDrawingController

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        let canvas = KitDrawingNSView(frame: NSRect(x: 0, y: 0, width: 400, height: DrawingDoc.defaultHeight))
        canvas.autoresizingMask = [.width]
        scroll.documentView = canvas
        controller.canvas = canvas
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let canvas = scroll.documentView as? KitDrawingNSView else { return }
        controller.canvas = canvas
        let binding = $doc
        canvas.onChange = { new in DispatchQueue.main.async { if binding.wrappedValue != new { binding.wrappedValue = new } } }
        canvas.setPen(color: color, width: width, erasing: erasing)
        canvas.paper = paper
        // The canvas is as wide as the visible area; a drawing made at another width is scaled to it
        let width = scroll.contentSize.width
        if width > 0, abs(canvas.frame.width - width) > 0.5 { canvas.setFrameSize(NSSize(width: width, height: canvas.frame.height)) }
        canvas.adopt(doc)
    }
}

final class KitDrawingNSView: NSView {
    private var recorder = DrawingRecorder()
    private let strokeUndo = UndoManager()
    var onChange: ((DrawingDoc) -> Void)?
    var paper = DrawingPaper.dark { didSet { if paper != oldValue { needsDisplay = true } } }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var undoManager: UndoManager? { strokeUndo }

    func setPen(color: String, width: Double, erasing: Bool) {
        recorder.color = color
        recorder.width = width
        recorder.erasing = erasing
    }

    /// Takes the drawing from outside (the note loaded, Clear, a drawing made at another width)
    func adopt(_ doc: DrawingDoc) {
        guard recorder.current == nil, recorder.doc != doc else { return }
        if doc.strokes.count != recorder.doc.strokes.count { strokeUndo.removeAllActions() }
        recorder.doc = doc
        recorder.adopt(width: Double(bounds.width))
        fitHeight()
        needsDisplay = true
    }

    private func fitHeight() {
        let h = CGFloat(max(recorder.doc.h, DrawingDoc.defaultHeight))
        if abs(frame.height - h) > 0.5 { setFrameSize(NSSize(width: frame.width, height: h)) }
    }

    override func setFrameSize(_ newSize: NSSize) {
        let widthChanged = abs(newSize.width - frame.width) > 0.5
        super.setFrameSize(newSize)
        if widthChanged, newSize.width > 0, recorder.current == nil {
            let before = recorder.doc
            recorder.adopt(width: Double(newSize.width))
            if recorder.doc != before { fitHeight(); onChange?(recorder.doc) }
            needsDisplay = true
        }
    }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }

    // ── Drawing ─────────────────────────────────────────────────────────────

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        DrawingRenderer.drawPaper(in: ctx, size: bounds.size, paper: paper)
        // The ink in its own layer, so the eraser clears ink and not the paper below it
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        for s in recorder.doc.strokes { DrawingRenderer.draw(s, in: ctx, paper: paper) }
        if let current = recorder.current { DrawingRenderer.draw(current, in: ctx, paper: paper) }
        ctx.endTransparencyLayer()
    }

    private func pressure(_ event: NSEvent) -> Double? {
        event.subtype == .tabletPoint ? Double(event.pressure) : nil
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let p = convert(event.locationInWindow, from: nil)
        recorder.begin(x: p.x, y: p.y, pressure: pressure(event))
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if recorder.add(x: p.x, y: p.y, pressure: pressure(event)) { fitHeight() }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if recorder.end() {
            strokeUndo.registerUndo(withTarget: self) { $0.undoStroke() }
            strokeUndo.setActionName("Undo Stroke")
            onChange?(recorder.doc)
        }
        needsDisplay = true
    }

    func undoStroke() {
        guard recorder.undo() else { return }
        needsDisplay = true
        onChange?(recorder.doc)
    }
}
