import SwiftUI
#if os(iOS)
import UIKit
#endif

// ── Editing canvas ───────────────────────────────────────────────────────────

#if os(iOS)

/// One finger (or Apple Pencil) draws; two fingers scroll. Grows by 800pt when you draw near
/// the bottom, like the web.
final class DrawingCanvasView: UIView {
    var strokes: [DrawingDoc.Stroke] = [] { didSet { setNeedsDisplay() } }
    var color = DrawingRenderer.colors[0]
    var penWidth: Double = 3
    var erasing = false
    var paper = DrawingPaper.dark { didSet { setNeedsDisplay() } }
    var onChange: (() -> Void)?
    var onNeedsMoreHeight: (() -> Void)?

    private var current: DrawingDoc.Stroke?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        isMultipleTouchEnabled = false
        contentMode = .redraw
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func point(_ touch: UITouch) -> DrawingDoc.Point {
        let loc = touch.preciseLocation(in: self)
        let pressure = touch.maximumPossibleForce > 0 && touch.type == .pencil
            ? min(1, max(0.1, Double(touch.force / touch.maximumPossibleForce)))
            : 0.5
        return DrawingDoc.Point(x: Double(loc.x), y: Double(loc.y), p: pressure)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first else { return }
        current = DrawingDoc.Stroke(color: color, width: erasing ? DrawingRenderer.eraserWidth : penWidth, eraser: erasing, points: [point(t)])
        setNeedsDisplay()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first, current != nil else { return }
        for c in event?.coalescedTouches(for: t) ?? [t] {
            let p = point(c)
            if let last = current?.points.last, (p.x - last.x) * (p.x - last.x) + (p.y - last.y) * (p.y - last.y) < 4 { continue }
            current?.points.append(p)
        }
        if let y = current?.points.last?.y, y > Double(bounds.height) - 300 { onNeedsMoreHeight?() }
        setNeedsDisplay()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { finish() }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { current = nil; setNeedsDisplay() }

    private func finish() {
        guard let stroke = current else { return }
        current = nil
        if strokes.count < DrawingDoc.maxStrokes { strokes.append(stroke) }
        onChange?()
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        for s in strokes { DrawingRenderer.draw(s, in: ctx, paper: paper) }
        if let current { DrawingRenderer.draw(current, in: ctx, paper: paper) }
    }
}

/// Paper behind the canvas (so the eraser removes ink, not the ruled lines)
final class PaperView: UIView {
    var paper = DrawingPaper.dark { didSet { setNeedsDisplay() } }
    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        DrawingRenderer.drawPaper(in: ctx, size: bounds.size, paper: paper)
    }
}

/// Lays the paper and canvas out whenever its own size is known or changes
final class DrawingScrollView: UIScrollView {
    var onLayout: ((CGFloat) -> Void)?
    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?(bounds.width)
    }
}

/// Scrollable drawing surface for SwiftUI
struct DrawingSurface: UIViewRepresentable {
    @Binding var doc: DrawingDoc
    let color: String
    let penWidth: Double
    let erasing: Bool
    let paper: DrawingPaper

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> DrawingScrollView {
        let scroll = DrawingScrollView()
        scroll.panGestureRecognizer.minimumNumberOfTouches = 2 // one finger draws
        scroll.delaysContentTouches = false
        scroll.backgroundColor = UIColor(cgColor: paper.ground)
        scroll.alwaysBounceVertical = true
        let paper = PaperView()
        paper.contentMode = .redraw
        let canvas = DrawingCanvasView()
        scroll.addSubview(paper)
        scroll.addSubview(canvas)
        context.coordinator.scroll = scroll
        context.coordinator.paper = paper
        context.coordinator.canvas = canvas
        canvas.onChange = { [weak coordinator = context.coordinator] in coordinator?.strokesChanged() }
        canvas.onNeedsMoreHeight = { [weak coordinator = context.coordinator] in coordinator?.grow() }
        scroll.onLayout = { [weak coordinator = context.coordinator] width in coordinator?.layoutIfNeeded(width: width) }
        return scroll
    }

    func updateUIView(_ scroll: DrawingScrollView, context: Context) {
        context.coordinator.parent = self
        let c = context.coordinator
        c.canvas?.color = color
        c.canvas?.penWidth = penWidth
        c.canvas?.erasing = erasing
        c.canvas?.paper = paper
        c.paper?.paper = paper
        scroll.backgroundColor = UIColor(cgColor: paper.ground)
        c.layoutIfNeeded(width: scroll.bounds.width)
        if c.canvas?.strokes != doc.strokes { c.canvas?.strokes = doc.strokes }
        scroll.setNeedsLayout()
    }

    final class Coordinator {
        var parent: DrawingSurface
        weak var scroll: UIScrollView?
        weak var paper: PaperView?
        weak var canvas: DrawingCanvasView?
        init(_ parent: DrawingSurface) { self.parent = parent }

        /// First layout: adopt the view's width (rescaling a drawing made at another width)
        func layoutIfNeeded(width: CGFloat) {
            guard width > 0 else { return }
            var doc = parent.doc
            if abs(doc.w - Double(width)) > 0.5 {
                doc = doc.scaled(toWidth: Double(width))
                canvas?.strokes = doc.strokes
                let scaled = doc
                DispatchQueue.main.async { self.parent.doc = scaled }
            }
            let height = CGFloat(max(doc.h, DrawingDoc.defaultHeight))
            let frame = CGRect(x: 0, y: 0, width: width, height: height)
            if paper?.frame != frame {
                paper?.frame = frame
                canvas?.frame = frame
                scroll?.contentSize = frame.size
                paper?.setNeedsDisplay()
            }
        }

        func strokesChanged() {
            parent.doc.strokes = canvas?.strokes ?? []
        }

        func grow() {
            parent.doc.h += 800
        }
    }
}
#else
/// The Mac's drawing surface: draw with the mouse or trackpad, scroll with the scroll wheel or two
/// fingers. Grows by 800pt when you draw near the bottom, like the web and the iPhone.
struct DrawingSurface: View {
    @Binding var doc: DrawingDoc
    let color: String
    let penWidth: Double
    let erasing: Bool
    let paper: DrawingPaper

    @State private var current: DrawingDoc.Stroke?

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                let height = CGFloat(max(doc.h, DrawingDoc.defaultHeight))
                ZStack(alignment: .topLeading) {
                    Canvas { ctx, size in
                        ctx.withCGContext { DrawingRenderer.drawPaper(in: $0, size: size, paper: paper) }
                    }
                    // Ink in its own layer, so the eraser clears ink and not the paper below it
                    Canvas { ctx, _ in
                        ctx.withCGContext { cg in
                            for s in doc.strokes { DrawingRenderer.draw(s, in: cg, paper: paper) }
                            if let current { DrawingRenderer.draw(current, in: cg, paper: paper) }
                        }
                    }
                    .drawingGroup()
                }
                .frame(width: geo.size.width, height: height)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { v in draw(at: v.location, height: height) }
                    .onEnded { _ in finish() })
            }
            .background(Color(cgColor: paper.ground))
            .onAppear { adopt(width: geo.size.width) }
            .onChange(of: geo.size.width) { _, w in adopt(width: w) }
        }
    }

    /// Rescale a drawing made at another width to this one, as the iPhone canvas does
    private func adopt(width: CGFloat) {
        guard width > 0, abs(doc.w - Double(width)) > 0.5 else { return }
        doc = doc.scaled(toWidth: Double(width))
    }

    private func draw(at loc: CGPoint, height: CGFloat) {
        let p = DrawingDoc.Point(x: Double(loc.x), y: Double(loc.y), p: 0.5)
        if current == nil {
            current = DrawingDoc.Stroke(color: color, width: erasing ? DrawingRenderer.eraserWidth : penWidth, eraser: erasing, points: [p])
            return
        }
        if let last = current?.points.last, (p.x - last.x) * (p.x - last.x) + (p.y - last.y) * (p.y - last.y) < 4 { return }
        current?.points.append(p)
        if p.y > Double(height) - 300 { doc.h = max(doc.h, DrawingDoc.defaultHeight) + 800 }
    }

    private func finish() {
        guard let stroke = current else { return }
        current = nil
        if doc.strokes.count < DrawingDoc.maxStrokes { doc.strokes.append(stroke) }
    }
}
#endif

// ── Full-screen editor ───────────────────────────────────────────────────────

/// The web's draw panel: colours, S/M/L, eraser, undo, clear
struct DrawingEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    @Environment(AppState.self) private var app
    @State var doc: DrawingDoc
    let done: (DrawingDoc) -> Void

    @State private var color = DrawingRenderer.colors[0]
    @State private var size: Double = 3
    @State private var erasing = false
    @State private var confirmClear = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                toolbar
                DrawingSurface(doc: $doc, color: color, penWidth: size, erasing: erasing, paper: app.drawingPaper)
                    .ignoresSafeArea(edges: .bottom)
            }
            .background(theme.page)
            .themedNavBar(theme, title: "Draw")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { done(doc); dismiss() }.fontWeight(.semibold)
                }
            }
            .confirmationDialog("Clear the whole drawing?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Clear", role: .destructive) { doc.strokes = [] }
            }
        }
    }

    private var toolbar: some View {
        DrawingToolbar(color: $color, size: $size, erasing: $erasing, paper: app.drawingPaper, canUndo: !doc.strokes.isEmpty,
                       undo: { doc.strokes.removeLast() }, clear: { confirmClear = true })
            .overlay(alignment: .bottom) { RowDivider() }
    }
}

/// A drawing on its ruled paper, sized to the width it's shown at
struct DrawingImage: View {
    let doc: DrawingDoc
    let paper: DrawingPaper
    @State private var width: CGFloat = 0

    /// Same height rule as DrawingRenderer.image: down to the lowest ink plus a margin, at least 200pt
    private var height: CGFloat {
        guard width > 0, doc.w > 0 else { return 200 }
        let inkBottom = doc.strokes.flatMap(\.points).map(\.y).max() ?? 0
        return max(200, CGFloat((inkBottom + 60) * Double(width) / doc.w))
    }

    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .overlay {
                if width > 0 {
                    #if os(iOS)
                    Image(uiImage: DrawingRenderer.image(doc, width: width, paper: paper)).resizable()
                    #else
                    ZStack {
                        Canvas { ctx, size in ctx.withCGContext { DrawingRenderer.drawPaper(in: $0, size: size, paper: paper) } }
                        Canvas { ctx, _ in
                            let k = doc.w > 0 ? Double(width) / doc.w : 1
                            ctx.withCGContext { cg in for s in doc.strokes { DrawingRenderer.draw(s, in: cg, scale: k, paper: paper) } }
                        }
                        .drawingGroup()
                    }
                    #endif
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
