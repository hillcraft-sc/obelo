import Testing
import CoreGraphics
@testable import ObeloShared

// Handwriting paper: which paper a setting and theme give, and the ink on each
@Suite struct DrawingPaperTests {
    @Test func followsTheThemeByDefault() {
        #expect(DrawingPaper.resolve(nil, theme: .darkDefault).isDark)
        #expect(!DrawingPaper.resolve(nil, theme: .lightDefault).isDark)
        #expect(DrawingPaper.resolve("theme", theme: .lightDefault).isDark == false)
        #expect(DrawingPaper.resolve("sepia", theme: .lightDefault).isDark == false) // unknown = theme
    }

    @Test func darkAndWhiteAreFixed() {
        #expect(DrawingPaper.resolve("dark", theme: .lightDefault) == .dark)
        #expect(DrawingPaper.resolve("white", theme: .darkDefault) == .white)
    }

    @Test func onDarkPaperInkIsAsStored() {
        for c in DrawingRenderer.colors { #expect(DrawingPaper.dark.ink(c) == c) }
    }

    @Test func onLightPaperTheFourPensGetDarkerShades() {
        let shades = DrawingRenderer.colors.map { DrawingPaper.white.ink($0) }
        #expect(shades == ["#0f172a", "#2563eb", "#dc2626", "#16a34a"])
        #expect(DrawingPaper.white.ink("#F1F5F9") == "#0f172a") // case doesn't matter
        #expect(DrawingPaper.white.ink("#123456") == "#123456") // other colours are left alone
    }

    @Test func aMatchingThemePaperUsesTheThemesOwnColours() {
        let light = DrawingPaper.resolve("theme", theme: .lightDefault)
        #expect(light != .white) // the theme's page colour, not pure white
        #expect(light.ground != DrawingPaper.dark.ground)
    }
}
