import SwiftUI
#if os(iOS)
import UIKit
#endif

// Handwritten notes, in the web canvas's format (views/notes/form.ejs) so a drawing made on either
// side opens on the other: { v: 1, w, h, strokes: [{ color, width, eraser, points: [{ x, y, p }] }] }
// where x/y are points on a canvas w wide, and p is pen pressure (0.1–1, 0.5 for a finger).
// Rendering matches the web: line width = width × average pressure × 2, round caps, quadratic
// curves through midpoints, and the eraser clears pixels.

struct DrawingDoc: Codable, Equatable {
    struct Point: Codable, Equatable { var x: Double; var y: Double; var p: Double? }
    struct Stroke: Codable, Equatable {
        var color: String
        var width: Double
        var eraser: Bool?
        var points: [Point]
    }
    var v = 1
    var w: Double
    var h: Double
    var strokes: [Stroke]

    static let defaultHeight: Double = 1200
    static let maxStrokes = 500

    static func decode(_ json: String?) -> DrawingDoc? {
        guard let data = json?.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(DrawingDoc.self, from: data)
    }

    /// Compact JSON like the web saves (rounded coordinates)
    func encoded() -> String? {
        var copy = self
        copy.strokes = strokes.map { s in
            var s = s
            s.points = s.points.map { Point(x: $0.x.rounded(), y: $0.y.rounded(), p: (($0.p ?? 0.5) * 100).rounded() / 100) }
            return s
        }
        guard let data = try? JSONEncoder().encode(copy) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// The same drawing on a canvas `width` wide (the web stores the width it was drawn at)
    func scaled(toWidth width: Double) -> DrawingDoc {
        guard w > 0, abs(width - w) > 0.5 else { return self }
        let k = width / w
        return DrawingDoc(v: v, w: width, h: h * k, strokes: strokes.map { s in
            var s = s
            s.points = s.points.map { Point(x: $0.x * k, y: $0.y * k, p: $0.p) }
            return s
        })
    }
}

/// The paper a drawing is shown on, and so the shade each pen is drawn in. The setting is
/// "Handwriting paper" (Settings > Notes, saved on the account: `theme` = follow the theme, `dark`
/// or `white`). A drawing always stores the four dark-paper colours (`DrawingRenderer.colors`);
/// on light paper they are drawn in darker shades of the same role, so a drawing reads on either
/// paper and on a client that hasn't got this. The same mapping is in public/js/note-paper.js.
struct DrawingPaper: Equatable {
    var ground: CGColor
    var rule: CGColor
    var isDark: Bool

    static func == (a: DrawingPaper, b: DrawingPaper) -> Bool {
        a.isDark == b.isDark && CFEqual(a.ground, b.ground) && CFEqual(a.rule, b.rule)
    }

    private static func hex(_ v: UInt32) -> CGColor {
        CGColor(red: CGFloat((v >> 16) & 0xff) / 255, green: CGFloat((v >> 8) & 0xff) / 255, blue: CGFloat(v & 0xff) / 255, alpha: 1)
    }

    static let dark = DrawingPaper(ground: hex(0x0f172a), rule: hex(0x182035), isDark: true)
    static let white = DrawingPaper(ground: hex(0xffffff), rule: hex(0xe2e8f0), isDark: false)

    /// `choice` is the saved setting ("theme", "dark", "white"; anything else, or nothing saved
    /// yet on a server that doesn't have the setting, means "theme")
    static func resolve(_ choice: String?, theme: Theme) -> DrawingPaper {
        switch choice {
        case "dark": return .dark
        case "white": return .white
        default:
            return DrawingPaper(ground: PlatformColor(theme.page).cgColor, rule: PlatformColor(theme.border1).cgColor, isDark: theme.isDark)
        }
    }

    /// The shades the four stored pen colours take on light paper
    static let onLight = ["#f1f5f9": "#0f172a", "#93c5fd": "#2563eb", "#fca5a5": "#dc2626", "#86efac": "#16a34a"]

    /// The colour to draw a stored pen colour in on this paper (others are left alone)
    func ink(_ stored: String) -> String {
        isDark ? stored : (Self.onLight[stored.lowercased()] ?? stored)
    }
}

enum DrawingRenderer {
    /// The web's colours and sizes (toolbar in notes/form.ejs)
    static let colors = ["#f1f5f9", "#93c5fd", "#fca5a5", "#86efac"]
    static let sizes: [(String, Double)] = [("S", 1.5), ("M", 3), ("L", 6)]
    static let eraserWidth: Double = 20

    static func draw(_ stroke: DrawingDoc.Stroke, in ctx: CGContext, scale k: Double = 1, paper: DrawingPaper = .dark) {
        let pts = stroke.points
        guard !pts.isEmpty else { return }
        ctx.saveGState()
        ctx.setBlendMode(stroke.eraser == true ? .clear : .normal)
        let color = PlatformColor(Color(hex: paper.ink(stroke.color))).cgColor
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        if pts.count == 1 {
            let r = stroke.width * (pts[0].p ?? 0.5) * k
            ctx.setFillColor(color)
            ctx.fillEllipse(in: CGRect(x: pts[0].x * k - r, y: pts[0].y * k - r, width: r * 2, height: r * 2))
        } else {
            let avg = pts.reduce(0) { $0 + ($1.p ?? 0.5) } / Double(pts.count)
            ctx.setStrokeColor(color)
            ctx.setLineWidth(stroke.width * avg * 2 * k)
            ctx.move(to: CGPoint(x: pts[0].x * k, y: pts[0].y * k))
            if pts.count == 2 {
                ctx.addLine(to: CGPoint(x: pts[1].x * k, y: pts[1].y * k))
            } else {
                for i in 1..<(pts.count - 1) {
                    let mid = CGPoint(x: (pts[i].x + pts[i + 1].x) / 2 * k, y: (pts[i].y + pts[i + 1].y) / 2 * k)
                    ctx.addQuadCurve(to: mid, control: CGPoint(x: pts[i].x * k, y: pts[i].y * k))
                }
                ctx.addLine(to: CGPoint(x: pts[pts.count - 1].x * k, y: pts[pts.count - 1].y * k))
            }
            ctx.strokePath()
        }
        ctx.restoreGState()
    }

    /// Ruled paper like the web canvas: lines every 36pt
    static func drawPaper(in ctx: CGContext, size: CGSize, paper: DrawingPaper = .dark) {
        ctx.setFillColor(paper.ground)
        ctx.fill(CGRect(origin: .zero, size: size))
        ctx.setFillColor(paper.rule)
        var y: CGFloat = 35
        while y < size.height { ctx.fill(CGRect(x: 0, y: y, width: size.width, height: 1)); y += 36 }
    }

    #if os(iOS)
    /// The whole drawing as an image `width` wide: paper, then ink (erasing ink, not paper)
    static func image(_ doc: DrawingDoc, width: CGFloat, trimToInk: Bool = true, paper: DrawingPaper = .dark) -> UIImage {
        let k = doc.w > 0 ? Double(width) / doc.w : 1
        let inkBottom = doc.strokes.flatMap(\.points).map(\.y).max() ?? 0
        let height = trimToInk ? max(200, CGFloat((inkBottom + 60) * k)) : CGFloat(doc.h * k)
        let size = CGSize(width: width, height: height)
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        let ink = UIGraphicsImageRenderer(size: size, format: format).image { r in
            for s in doc.strokes { draw(s, in: r.cgContext, scale: k, paper: paper) }
        }
        return UIGraphicsImageRenderer(size: size, format: format).image { r in
            drawPaper(in: r.cgContext, size: size, paper: paper)
            ink.draw(at: .zero)
        }
    }
    #endif
}
