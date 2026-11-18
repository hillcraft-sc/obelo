import SwiftUI

// A port of the web app's theme system (src/views/layouts/main.ejs): each theme is a set of
// surface, border, muted-text and accent colours, and the web's Tailwind class names map onto
// them. Names here follow the Tailwind classes the web uses, so views read like their EJS twins
// (gray900 = card surface, indigo400 = accent text, and so on).

struct Theme: Equatable {
    let id: String
    let isDark: Bool

    // Backgrounds: page (gray-950), surface (gray-900), elevated (gray-800), hover levels
    let page: Color
    let surface: Color
    let elevated: Color
    let h1: Color       // gray-750
    let h2: Color       // gray-700
    let h3: Color       // gray-600

    // Borders: gray-800 / 700 / 600
    let border1: Color
    let border2: Color
    let border3: Color

    // Text
    let textPrimary: Color   // text-white
    let text100: Color
    let text200: Color
    let text300: Color
    let text400: Color
    let textMuted: Color     // text-gray-500 / 600 / 700
    let placeholder: Color

    // Accent (the web's indigo-* classes)
    let accent: Color        // bg-indigo-600
    let accentHover: Color   // bg-indigo-500
    let accentDark: Color    // bg-indigo-700
    let accentSurface: Color // bg-indigo-950
    let accentText: Color    // text-indigo-400
    let accentTextLight: Color // text-indigo-300
    let accentBorder9: Color // border-indigo-900
    var onAccent: Color = .white // text on accent fills (dark on Catppuccin's pastel accent)

    var colorScheme: ColorScheme { isDark ? .dark : .light }

    // Status colours (priority dots, overdue, done, warnings). Tailwind's shades, except in the
    // Catppuccin themes, which use Catppuccin's own unless the user picked "Classic (Tailwind)".
    var status: StatusPalette = .tailwind
    var red300: Color { status.red300 }
    var red400: Color { status.red400 }
    var red500: Color { status.red500 }
    var red700: Color { status.red700 }
    var red800: Color { status.red800 }
    var red950: Color { status.red950 }
    var green300: Color { status.green300 }
    var green400: Color { status.green400 }
    var green500: Color { status.green500 }
    var green700: Color { status.green700 }
    var green800: Color { status.green800 }
    var green950: Color { status.green950 }
    var amber300: Color { status.amber300 }
    var amber400: Color { status.amber400 }
    var amber500: Color { status.amber500 }
    var amber900: Color { status.amber900 }
    var amber950: Color { status.amber950 }
    var yellow400: Color { status.yellow400 }
    var orange500: Color { status.orange500 }
    var orange800: Color { status.orange800 }
    var blue400: Color { status.blue400 }
    var blue500: Color { status.blue500 }
    /// Text on a solid status fill (e.g. the red delete button)
    var onStatusFill: Color { status.onFill }

    func priorityDot(_ priority: String) -> Color {
        switch priority {
        case "high": red500
        case "medium": amber500
        case "low": blue500
        default: h3
        }
    }
}

extension Theme {
    private static let darkText = (
        white: Color.white, g100: Color(hex: "#f3f4f6"), g200: Color(hex: "#e5e7eb"),
        g300: Color(hex: "#d1d5db"), g400: Color(hex: "#9ca3af")
    )

    private static func dark(
        id: String, pg: String, sf: String, el: String, h1: String, h2: String, h3: String,
        bd1: String, bd2: String, bd3: String, muted: String, ph: String,
        ac: String, acH: String, acD: String, acSf: String, acT4: String, acT3: String, acBd9: String,
        text: (p: String, s1: String, s2: String, s3: String, s4: String)? = nil, onAccent: String? = nil
    ) -> Theme {
        Theme(
            id: id, isDark: true,
            page: Color(hex: pg), surface: Color(hex: sf), elevated: Color(hex: el),
            h1: Color(hex: h1), h2: Color(hex: h2), h3: Color(hex: h3),
            border1: Color(hex: bd1), border2: Color(hex: bd2), border3: Color(hex: bd3),
            textPrimary: text.map { Color(hex: $0.p) } ?? darkText.white,
            text100: text.map { Color(hex: $0.s1) } ?? darkText.g100,
            text200: text.map { Color(hex: $0.s2) } ?? darkText.g200,
            text300: text.map { Color(hex: $0.s3) } ?? darkText.g300,
            text400: text.map { Color(hex: $0.s4) } ?? darkText.g400,
            textMuted: Color(hex: muted), placeholder: Color(hex: ph),
            accent: Color(hex: ac), accentHover: Color(hex: acH), accentDark: Color(hex: acD),
            accentSurface: Color(hex: acSf), accentText: Color(hex: acT4), accentTextLight: Color(hex: acT3),
            accentBorder9: Color(hex: acBd9), onAccent: onAccent.map { Color(hex: $0) } ?? .white
        )
    }

    private static func light(
        id: String, pg: String, sf: String, el: String, h1: String, h2: String, h3: String,
        bd1: String, bd2: String, bd3: String, p: String, s1: String, s2: String, s3: String, s4: String,
        muted: String, ph: String,
        ac: String, acH: String, acD: String, acSf: String, acT4: String, acT3: String, acBd9: String
    ) -> Theme {
        Theme(
            id: id, isDark: false,
            page: Color(hex: pg), surface: Color(hex: sf), elevated: Color(hex: el),
            h1: Color(hex: h1), h2: Color(hex: h2), h3: Color(hex: h3),
            border1: Color(hex: bd1), border2: Color(hex: bd2), border3: Color(hex: bd3),
            textPrimary: Color(hex: p), text100: Color(hex: s1), text200: Color(hex: s2),
            text300: Color(hex: s3), text400: Color(hex: s4),
            textMuted: Color(hex: muted), placeholder: Color(hex: ph),
            accent: Color(hex: ac), accentHover: Color(hex: acH), accentDark: Color(hex: acD),
            accentSurface: Color(hex: acSf), accentText: Color(hex: acT4), accentTextLight: Color(hex: acT3),
            accentBorder9: Color(hex: acBd9)
        )
    }

    static let darkDefault = dark(
        id: "dark", pg: "#0f1117", sf: "#1a1d27", el: "#252836", h1: "#2d3246", h2: "#353a56", h3: "#3e4366",
        bd1: "#2e3349", bd2: "#3a3f5c", bd3: "#474d6e", muted: "#6a7292", ph: "#555d7c",
        ac: "#2563eb", acH: "#3b7fff", acD: "#1d4ed8", acSf: "#0c1852", acT4: "#93bbff", acT3: "#bdd3ff", acBd9: "#1a3a8a")

    static let midnight = dark(
        id: "midnight", pg: "#0a0b12", sf: "#13151f", el: "#1d2030", h1: "#252740", h2: "#2d2f50", h3: "#363960",
        bd1: "#272a3e", bd2: "#333652", bd3: "#404468", muted: "#676a88", ph: "#4d5070",
        ac: "#7c3aed", acH: "#9555ff", acD: "#6d28d9", acSf: "#2d1a5c", acT4: "#c4a8ff", acT3: "#dac8ff", acBd9: "#4c1d95")

    static let mocha = dark(
        id: "mocha", pg: "#1c1410", sf: "#261c15", el: "#33241b", h1: "#3c2c22", h2: "#453329", h3: "#4e3b30",
        bd1: "#3d2b1f", bd2: "#4a3427", bd3: "#5a3f30", muted: "#8c6b45", ph: "#6a4f33",
        ac: "#b45309", acH: "#d06010", acD: "#92400e", acSf: "#451a03", acT4: "#f5b86e", acT3: "#fcd28e", acBd9: "#78350f")

    static let forest = dark(
        id: "forest", pg: "#0d1a0f", sf: "#162419", el: "#1f3024", h1: "#27382c", h2: "#2f4034", h3: "#37493c",
        bd1: "#28402d", bd2: "#334e38", bd3: "#3f5e45", muted: "#5e8062", ph: "#476350",
        ac: "#15803d", acH: "#1a9e4c", acD: "#166534", acSf: "#052e16", acT4: "#6dd98a", acT3: "#9de8b0", acBd9: "#14532d")

    static let sunset = dark(
        id: "sunset", pg: "#1a0f0f", sf: "#231616", el: "#2e1e1e", h1: "#362525", h2: "#3e2c2c", h3: "#473333",
        bd1: "#3e2520", bd2: "#4c2f2a", bd3: "#5c3935", muted: "#8b6457", ph: "#6a4b40",
        ac: "#b94528", acH: "#d45530", acD: "#9a3920", acSf: "#3a1008", acT4: "#ffb38a", acT3: "#ffd0b0", acBd9: "#7f1d0f")

    static let amoled = dark(
        id: "amoled", pg: "#000000", sf: "#0d0d0d", el: "#141414", h1: "#1a1a1a", h2: "#1f1f1f", h3: "#252525",
        bd1: "#1c1c1c", bd2: "#242424", bd3: "#2e2e2e", muted: "#666666", ph: "#4a4a4a",
        ac: "#3b82f6", acH: "#60a5fa", acD: "#2563eb", acSf: "#0a1628", acT4: "#93c5fd", acT3: "#bfdbfe", acBd9: "#1e3a8a")

    static let lightDefault = light(
        id: "light", pg: "#f8fafc", sf: "#ffffff", el: "#f1f5f9", h1: "#e9eef5", h2: "#e2e8f0", h3: "#cbd5e1",
        bd1: "#e2e8f0", bd2: "#cbd5e1", bd3: "#94a3b8",
        p: "#0f172a", s1: "#1e293b", s2: "#334155", s3: "#475569", s4: "#64748b", muted: "#64748b", ph: "#94a3b8",
        ac: "#1e5fcc", acH: "#2563eb", acD: "#1a4fa8", acSf: "#eff6ff", acT4: "#1e5fcc", acT3: "#2563eb", acBd9: "#1e40af")

    static let breeze = light(
        id: "breeze", pg: "#dce9f7", sf: "#eef5fd", el: "#f5f9ff", h1: "#cfe0f2", h2: "#c1d6ed", h3: "#b0c8e6",
        bd1: "#93c4e8", bd2: "#7aaac5", bd3: "#5e92b5",
        p: "#12263f", s1: "#182e4a", s2: "#2c4a6a", s3: "#3a5f82", s4: "#4f7099", muted: "#4f7099", ph: "#6a8bb5",
        ac: "#0059b3", acH: "#006fd8", acD: "#004a96", acSf: "#e0f0ff", acT4: "#0059b3", acT3: "#006fd8", acBd9: "#1e3a8a")

    // Catppuccin (catppuccin.com) flavours, mauve accent; same values as the web's ctp-* themes
    static let ctpFrappe = dark(
        id: "ctp-frappe", pg: "#292c3c", sf: "#303446", el: "#414559", h1: "#494e63", h2: "#51576d", h3: "#626880",
        bd1: "#414559", bd2: "#51576d", bd3: "#626880", muted: "#838ba7", ph: "#737994",
        ac: "#ca9ee6", acH: "#c9abea", acD: "#ab89c6", acSf: "#47445e", acT4: "#ca9ee6", acT3: "#c8b2ec", acBd9: "#66597e",
        text: ("#c6d0f5", "#c6d0f5", "#b5bfe2", "#b5bfe2", "#a5adce"), onAccent: "#232634")

    static let ctpMacchiato = dark(
        id: "ctp-macchiato", pg: "#1e2030", sf: "#24273a", el: "#363a4f", h1: "#40445a", h2: "#494d64", h3: "#5b6078",
        bd1: "#363a4f", bd2: "#494d64", bd3: "#5b6078", muted: "#8087a2", ph: "#6e738d",
        ac: "#c6a0f6", acH: "#c7adf6", acD: "#a688d0", acSf: "#3c3956", acT4: "#c6a0f6", acT3: "#c8b4f6", acBd9: "#5d517c",
        text: ("#cad3f5", "#cad3f5", "#b8c0e0", "#b8c0e0", "#a5adcb"), onAccent: "#181926")

    static let ctpMocha = dark(
        id: "ctp-mocha", pg: "#181825", sf: "#1e1e2e", el: "#313244", h1: "#3b3d4f", h2: "#45475a", h3: "#585b70",
        bd1: "#313244", bd2: "#45475a", bd3: "#585b70", muted: "#7f849c", ph: "#6c7086",
        ac: "#cba6f7", acH: "#ccb2f6", acD: "#a88bcf", acSf: "#38324c", acT4: "#cba6f7", acT3: "#ccb9f6", acBd9: "#5b4e74",
        text: ("#cdd6f4", "#cdd6f4", "#bac2de", "#bac2de", "#a6adc8"), onAccent: "#11111b")

    static let ctpLatte = light(
        id: "ctp-latte", pg: "#dce0e8", sf: "#eff1f5", el: "#e6e9ef", h1: "#e1e5ec", h2: "#ccd0da", h3: "#bcc0cc",
        bd1: "#ccd0da", bd2: "#bcc0cc", bd3: "#acb0be",
        p: "#4c4f69", s1: "#4c4f69", s2: "#5c5f77", s3: "#5c5f77", s4: "#6c6f85", muted: "#6c6f85", ph: "#9ca0b0",
        ac: "#8839ef", acH: "#7a33d7", acD: "#6d2ebf", acSf: "#e5dff4", acT4: "#8839ef", acT3: "#7a33d7", acBd9: "#bc95f2")

    static let builtIn: [Theme] = [darkDefault, midnight, forest, mocha, sunset, amoled, ctpFrappe, ctpMacchiato, ctpMocha,
                                   lightDefault, breeze, ctpLatte]

    static let labels: [String: (label: String, desc: String)] = [
        "dark": ("Dark", "Classic dark"), "midnight": ("Midnight", "Deep indigo"),
        "forest": ("Forest", "Earthy green"), "mocha": ("Mocha", "Warm coffee"),
        "sunset": ("Sunset", "Warm amber glow"), "amoled": ("AMOLED", "Pure black"),
        "light": ("Light", "Clean white"), "breeze": ("Breeze", "Cool sky blue"),
        "ctp-frappe": ("Catppuccin Frappé", "Muted pastel dark"),
        "ctp-macchiato": ("Catppuccin Macchiato", "Deeper pastel dark"),
        "ctp-mocha": ("Catppuccin Mocha", "Darkest pastel"),
        "ctp-latte": ("Catppuccin Latte", "Soft pastel light"),
        "custom": ("Custom", "Your accent colour"),
    ]

    /// The theme for a user's saved appearance. "custom" is the dark or light base with the
    /// accent derived from one hex colour, exactly like customAccentVars() in config/themes.js.
    static func resolve(_ appearance: Appearance?) -> Theme {
        guard let appearance else { return darkDefault }
        if appearance.theme == "custom" {
            let base = appearance.customBase == "light" ? lightDefault : darkDefault
            return base.withAccent(hex: appearance.customAccent)
        }
        var theme = builtIn.first { $0.id == appearance.theme } ?? darkDefault
        if appearance.statusColors != "tailwind", let palette = StatusPalette.catppuccin[theme.id] { theme.status = palette }
        return theme
    }

    func withAccent(hex: String) -> Theme {
        let adjust = { (delta: Int) in Color(hex: Color.adjustHex(hex, delta)) }
        return Theme(
            id: "custom", isDark: isDark, page: page, surface: surface, elevated: elevated,
            h1: h1, h2: h2, h3: h3, border1: border1, border2: border2, border3: border3,
            textPrimary: textPrimary, text100: text100, text200: text200, text300: text300, text400: text400,
            textMuted: textMuted, placeholder: placeholder,
            accent: Color(hex: hex), accentHover: adjust(isDark ? 25 : -20), accentDark: adjust(-35),
            accentSurface: Color(hex: hex).opacity(0.15),
            accentText: adjust(isDark ? 70 : -15), accentTextLight: adjust(isDark ? 100 : -35),
            accentBorder9: adjust(-35), status: status
        )
    }
}

struct StatusPalette: Equatable {
    let red300: Color
    let red400: Color
    let red500: Color
    let red700: Color
    let red800: Color
    let red950: Color
    let green300: Color
    let green400: Color
    let green500: Color
    let green700: Color
    let green800: Color
    let green950: Color
    let amber300: Color
    let amber400: Color
    let amber500: Color
    let amber900: Color
    let amber950: Color
    let yellow400: Color
    let orange500: Color
    let orange800: Color
    let blue400: Color
    let blue500: Color
    let onFill: Color

    init(red300: String, red400: String, red500: String, red700: String, red800: String, red950: String, green300: String, green400: String, green500: String, green700: String, green800: String, green950: String, amber300: String, amber400: String, amber500: String, amber900: String, amber950: String, yellow400: String, orange500: String, orange800: String, blue400: String, blue500: String, onFill: String) {
        self.red300 = Color(hex: red300)
        self.red400 = Color(hex: red400)
        self.red500 = Color(hex: red500)
        self.red700 = Color(hex: red700)
        self.red800 = Color(hex: red800)
        self.red950 = Color(hex: red950)
        self.green300 = Color(hex: green300)
        self.green400 = Color(hex: green400)
        self.green500 = Color(hex: green500)
        self.green700 = Color(hex: green700)
        self.green800 = Color(hex: green800)
        self.green950 = Color(hex: green950)
        self.amber300 = Color(hex: amber300)
        self.amber400 = Color(hex: amber400)
        self.amber500 = Color(hex: amber500)
        self.amber900 = Color(hex: amber900)
        self.amber950 = Color(hex: amber950)
        self.yellow400 = Color(hex: yellow400)
        self.orange500 = Color(hex: orange500)
        self.orange800 = Color(hex: orange800)
        self.blue400 = Color(hex: blue400)
        self.blue500 = Color(hex: blue500)
        self.onFill = Color(hex: onFill)
    }

    static let tailwind = StatusPalette(red300: "#fca5a5", red400: "#f87171", red500: "#ef4444", red700: "#b91c1c", red800: "#991b1b", red950: "#450a0a", green300: "#86efac", green400: "#4ade80", green500: "#22c55e", green700: "#15803d", green800: "#166534", green950: "#052e16", amber300: "#fcd34d", amber400: "#fbbf24", amber500: "#f59e0b", amber900: "#78350f", amber950: "#451a03", yellow400: "#facc15", orange500: "#f97316", orange800: "#9a3412", blue400: "#60a5fa", blue500: "#3b82f6", onFill: "#ffffff")

    /// Catppuccin per flavour (red, green, yellow, peach, maroon, blue), the same values as the
    /// web's --st-* variables
    static let catppuccin: [String: StatusPalette] = [
        "ctp-latte": StatusPalette(red300: "#a3254a", red400: "#d20f39", red500: "#d20f39", red700: "#d20f39", red800: "#e397aa", red950: "#ebd1db", green300: "#448441", green400: "#40a02b", green500: "#40a02b", green700: "#40a02b", green800: "#a9d1a4", green950: "#d6e6d9", amber300: "#ac7838", amber400: "#df8e1d", amber500: "#df8e1d", amber900: "#e9c99f", amber950: "#ede3d7", yellow400: "#df8e1d", orange500: "#fe640b", orange800: "#e64553", blue400: "#1e66f5", blue500: "#1e66f5", onFill: "#ffffff"),
        "ctp-frappe": StatusPalette(red300: "#db9dac", red400: "#e78284", red500: "#e78284", red700: "#e78284", red800: "#79535f", red950: "#4a3f4f", green300: "#b1d1af", green400: "#a6d189", green500: "#a6d189", green700: "#a6d189", green800: "#5f7361", green950: "#414a4f", amber300: "#dacbb3", amber400: "#e5c890", amber500: "#e5c890", amber900: "#786f64", amber950: "#494950", yellow400: "#e5c890", orange500: "#ef9f76", orange800: "#ea999c", blue400: "#8caaee", blue500: "#8caaee", onFill: "#232634"),
        "ctp-macchiato": StatusPalette(red300: "#e1a2b7", red400: "#ed8796", red500: "#ed8796", red700: "#ed8796", red800: "#744d5f", red950: "#403447", green300: "#b3d8b7", green400: "#a6da95", green500: "#a6da95", green700: "#a6da95", green800: "#586f5e", green950: "#364047", amber300: "#e1d4bd", amber400: "#eed49f", amber500: "#eed49f", amber900: "#756c62", amber950: "#403f48", yellow400: "#eed49f", orange500: "#f5a97f", orange800: "#ee99a0", blue400: "#8aadf4", blue500: "#8aadf4", onFill: "#181926"),
        "ctp-mocha": StatusPalette(red300: "#e6a5c3", red400: "#f38ba8", red500: "#f38ba8", red700: "#f38ba8", red800: "#734a5f", red950: "#3c2d3f", green300: "#b4debe", green400: "#a6e3a1", green500: "#a6e3a1", green700: "#a6e3a1", green800: "#546d5c", green950: "#313a3e", amber300: "#eadec7", amber400: "#f9e2af", amber500: "#f9e2af", amber900: "#766c62", amber950: "#3d3940", yellow400: "#f9e2af", orange500: "#fab387", orange800: "#eba0ac", blue400: "#89b4fa", blue500: "#89b4fa", onFill: "#11111b"),
    ]
}

extension Color {
    init(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        let r = Double((v >> 16) & 0xff) / 255, g = Double((v >> 8) & 0xff) / 255, b = Double(v & 0xff) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }

    static func adjustHex(_ hex: String, _ delta: Int) -> String {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        let clamp = { (x: Int) in min(255, max(0, x)) }
        let r = clamp(Int((v >> 16) & 0xff) + delta), g = clamp(Int((v >> 8) & 0xff) + delta), b = clamp(Int(v & 0xff) + delta)
        return String(format: "#%02x%02x%02x", r, g, b)
    }
}

private struct ThemeKey: EnvironmentKey {
    static let defaultValue = Theme.darkDefault
}

extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}
