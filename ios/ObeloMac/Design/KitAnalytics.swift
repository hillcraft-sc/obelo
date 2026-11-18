import Charts
import SwiftUI

// The Analytics screen's pieces (web: analytics/index.ejs): summary tiles, thin rate bars, a column chart
// (stacked for "Completion Timing", single colour for "When You Complete Things"), a line chart, a day heatmap
// with five shades, and the little legend. Charts are Swift Charts; hovering a column or point shows its numbers.
// Every one takes plain values, so it knows nothing about the server.

/// How a rate is coloured: the text colour for the number, the fill for its bar
extension RateBand {
    func text(_ theme: Theme) -> Color {
        switch self {
        case .none: theme.textMuted
        case .good: theme.green400
        case .fair: theme.amber400
        case .low: theme.red400
        }
    }
    func fill(_ theme: Theme) -> Color {
        switch self {
        case .none: theme.h2
        case .good: theme.green500
        case .fair: theme.amber500
        case .low: theme.red500
        }
    }
}

/// A summary tile: small title, big value, small note. `hero` is the large one with the accent border.
struct KitStatTile: View {
    @Environment(\.theme) private var theme
    let title: String
    let value: String
    let note: String
    var valueColor: Color?
    var hero = false
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: hero ? 8 : 4) {
            Text(title).font(.system(size: hero ? 12 : 11, weight: hero ? .medium : .regular))
                .foregroundStyle(hero ? theme.text400 : theme.textMuted)
            Text(value).font(.system(size: hero ? 36 : compact ? 16 : 20, weight: hero ? .bold : .semibold))
                .foregroundStyle(valueColor ?? theme.text300).lineLimit(1).minimumScaleFactor(0.7)
            Text(note).font(.system(size: hero ? 12 : 11)).foregroundStyle(theme.textMuted).lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(hero ? 20 : 12)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(hero ? theme.accentHover : theme.border1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(value), \(note)")
    }
}

/// The thin progress bar under a rate (web: .rate-bar)
struct KitRateBar: View {
    @Environment(\.theme) private var theme
    let rate: Int

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(theme.h2)
                Capsule().fill(RateBand(rate).fill(theme)).frame(width: geo.size.width * CGFloat(min(100, max(0, rate))) / 100)
            }
        }
        .frame(height: 5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(rate) percent")
    }
}

/// One coloured part of a column
struct KitColumnPart: Hashable {
    let name: String
    let value: Int
    let color: Color
}

/// One column: a label under it and its parts, bottom to top
struct KitColumn: Identifiable, Hashable {
    let label: String
    let parts: [KitColumnPart]
    /// The first line of the hover box ("Week of Nov 3 · 12")
    let title: String
    var id: String { label }
    var total: Int { parts.reduce(0) { $0 + $1.value } }
}

/// The small legend above a chart: a square and a name for each colour
struct KitChartLegend: View {
    @Environment(\.theme) private var theme
    let items: [(name: String, color: Color)]

    var body: some View {
        KitFlowLayout(spacing: 14) {
            ForEach(items.indices, id: \.self) { i in
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2).fill(items[i].color).frame(width: 10, height: 10)
                    Text(items[i].name).font(.system(size: 12)).foregroundStyle(theme.textMuted)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// The box that follows the pointer over a chart
struct KitChartCallout: View {
    @Environment(\.theme) private var theme
    let title: String
    let lines: [(text: String, color: Color?)]

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(theme.text100)
            ForEach(lines.indices, id: \.self) { i in
                HStack(spacing: 5) {
                    if let c = lines[i].color { RoundedRectangle(cornerRadius: 2).fill(c).frame(width: 8, height: 8) }
                    Text(lines[i].text).font(.system(size: 11)).foregroundStyle(theme.text300)
                }
            }
        }
        .padding(8)
        .background(theme.elevated, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(theme.border2))
        .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
    }
}

/// Axis styling shared by the charts: a recessive grid and muted 10pt labels
private struct KitChartAxes: ViewModifier {
    @Environment(\.theme) private var theme
    var percent = false
    var labelEvery = 1

    func body(content: Content) -> some View {
        let styled = content
            .chartXAxis {
                AxisMarks { value in
                    AxisGridLine().foregroundStyle(theme.border1)
                    if value.index % labelEvery == 0 { AxisValueLabel().font(.system(size: 10)).foregroundStyle(theme.textMuted) }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: percent ? .stride(by: 25) : .automatic(desiredCount: 4)) { value in
                    AxisGridLine().foregroundStyle(theme.border1)
                    AxisValueLabel { if let v = value.as(Int.self) { Text(percent ? "\(v)%" : "\(v)") } }
                        .font(.system(size: 10)).foregroundStyle(theme.textMuted)
                }
            }
        if percent { styled.chartYScale(domain: 0...100) } else { styled }
    }
}

/// Columns on a common baseline, stacked when a column has several parts. Hover a column for its numbers.
struct KitColumnChart: View {
    let columns: [KitColumn]
    var height: CGFloat = 200
    /// Show every Nth label under the columns (the hours chart has twelve, the weeks up to thirteen)
    var labelEvery = 1
    var summary: String
    @State private var hovered: String?

    var body: some View {
        Chart {
            ForEach(columns) { c in
                ForEach(c.parts.filter { $0.value > 0 }, id: \.self) { p in
                    BarMark(x: .value("Column", c.label), y: .value("Items", p.value), width: .ratio(0.6))
                        .foregroundStyle(p.color)
                        .opacity(hovered == nil || hovered == c.label ? 1 : 0.35)
                }
            }
            if let hovered, let c = columns.first(where: { $0.label == hovered }) {
                RuleMark(x: .value("Column", hovered)).foregroundStyle(.clear)
                    .annotation(position: .top, spacing: 4, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        KitChartCallout(title: c.title, lines: c.parts.filter { $0.value > 0 }.map { ("\($0.name): \($0.value)", $0.color) })
                    }
            }
        }
        .chartXSelection(value: $hovered)
        .modifier(KitChartAxes(labelEvery: labelEvery))
        .frame(height: height)
        .accessibilityLabel(summary)
    }
}

/// One point of a line
struct KitLinePoint: Identifiable, Hashable {
    let label: String
    /// nil is a gap (a week with nothing to rate)
    let value: Int?
    /// The hover box's second line ("75% on time (8 items)")
    let detail: String
    var id: String { label }
}

/// A smooth line with a soft fill under it. `percent` fixes the scale to 0 to 100%. Hover a point for its numbers.
struct KitLineChart: View {
    @Environment(\.theme) private var theme
    let points: [KitLinePoint]
    var color: Color
    var percent = false
    var height: CGFloat = 160
    var labelEvery = 1
    var calloutTitle: (String) -> String = { "Week of \($0)" }
    var summary: String
    @State private var hovered: String?

    var body: some View {
        Chart {
            ForEach(points.filter { $0.value != nil }) { p in
                AreaMark(x: .value("Week", p.label), y: .value("Value", p.value ?? 0))
                    .foregroundStyle(color.opacity(0.12)).interpolationMethod(.catmullRom)
                LineMark(x: .value("Week", p.label), y: .value("Value", p.value ?? 0))
                    .foregroundStyle(color).lineStyle(StrokeStyle(lineWidth: 2)).interpolationMethod(.catmullRom)
                PointMark(x: .value("Week", p.label), y: .value("Value", p.value ?? 0))
                    .foregroundStyle(color).symbolSize(hovered == p.label ? 80 : 30)
            }
            if let hovered, let p = points.first(where: { $0.label == hovered }) {
                RuleMark(x: .value("Week", hovered)).foregroundStyle(theme.border3)
                    .annotation(position: .top, spacing: 4, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        KitChartCallout(title: calloutTitle(p.label), lines: [(p.detail, nil)])
                    }
            }
        }
        .chartXSelection(value: $hovered)
        .modifier(KitChartAxes(percent: percent, labelEvery: labelEvery))
        .frame(height: height)
        .accessibilityLabel(summary)
    }
}

/// One day of the activity heatmap
struct KitShadeCell: Hashable {
    /// 0 (nothing) to 4 (most)
    let intensity: Int
    let isFuture: Bool
    let tooltip: String
}

/// Day squares in weeks, five shades of the accent, with day names down the left and a week label above every
/// fourth column (web: "Activity Heatmap")
struct KitShadeHeatmap: View {
    @Environment(\.theme) private var theme
    let weeks: [[KitShadeCell]]
    let dayLabels: [String]
    let weekLabels: [String]
    var summary: String
    @State private var width: CGFloat = 0

    private let gap: CGFloat = 4
    private let labelWidth: CGFloat = 22

    /// Squares share the width they are given, never bigger than 20pt or smaller than 10pt
    private var size: CGFloat {
        guard !weeks.isEmpty, width > 0 else { return 14 }
        return min(20, max(10, (width - labelWidth - gap * CGFloat(weeks.count)) / CGFloat(weeks.count)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: gap) {
                VStack(alignment: .trailing, spacing: gap) {
                    Color.clear.frame(width: labelWidth - 4, height: 14)
                    ForEach(dayLabels.indices, id: \.self) { i in
                        Text(i % 2 == 1 ? dayLabels[i] : "").font(.system(size: 9)).foregroundStyle(theme.textMuted)
                            .frame(width: labelWidth - 4, height: size, alignment: .trailing)
                    }
                }
                ForEach(weeks.indices, id: \.self) { w in
                    VStack(spacing: gap) {
                        Text(w % 4 == 0 && w < weekLabels.count ? weekLabels[w] : "")
                            .font(.system(size: 9)).foregroundStyle(theme.textMuted)
                            .fixedSize().frame(width: size, height: 14, alignment: .leading)
                        ForEach(weeks[w].indices, id: \.self) { d in
                            let cell = weeks[w][d]
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(shade(cell.isFuture ? 0 : cell.intensity))
                                .opacity(cell.isFuture ? 0.35 : 1)
                                .frame(width: size, height: size)
                                .help(cell.tooltip)
                        }
                    }
                }
            }
            HStack(spacing: 6) {
                Text("Less").font(.system(size: 10)).foregroundStyle(theme.textMuted)
                ForEach(0..<5, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 3, style: .continuous).fill(shade(i)).frame(width: 12, height: 12)
                }
                Text("More").font(.system(size: 10)).foregroundStyle(theme.textMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary)
    }

    private func shade(_ level: Int) -> Color {
        switch level {
        case 1: theme.accent.opacity(0.2)
        case 2: theme.accent.opacity(0.45)
        case 3: theme.accent.opacity(0.7)
        case 4: theme.accent
        default: theme.elevated
        }
    }
}
