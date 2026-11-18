import SwiftUI

// Small charts (web: the heatmap and the weekly bars on routines/show.ejs). They take plain values, so the
// Analytics screen can use them too.

/// One square of the heatmap
struct KitHeatCell: Hashable {
    enum Kind { case done, missed, notScheduled, future }
    let kind: Kind
    /// Shown on hover ("Nov 3 ✓")
    let tooltip: String
}

/// A grid of day squares, one column per week (web: "Last 12 weeks"). Green when done, dim when missed,
/// fainter when not scheduled, empty for the future.
struct KitHeatmap: View {
    @Environment(\.theme) private var theme
    let weeks: [[KitHeatCell]]
    /// The captions under the grid: the first week's date at the left, "Today" at the right
    var leadingCaption: String = ""
    var trailingCaption: String = "Today"
    /// What VoiceOver says for the whole grid ("Last 12 weeks: 31 of 60 scheduled days done")
    var summary: String
    @State private var width: CGFloat = 0

    /// The squares share the width they are given (never bigger than 22pt, never smaller than 8pt)
    private var size: CGFloat {
        guard !weeks.isEmpty, width > 0 else { return 13 }
        return min(22, max(8, (width - 4 * CGFloat(weeks.count - 1)) / CGFloat(weeks.count)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 4) {
                ForEach(weeks.indices, id: \.self) { w in
                    VStack(spacing: 4) {
                        ForEach(weeks[w].indices, id: \.self) { d in
                            let cell = weeks[w][d]
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(fill(cell.kind))
                                .frame(width: size, height: size)
                                .help(cell.tooltip)
                        }
                    }
                }
            }
            HStack {
                Text(leadingCaption)
                Spacer()
                Text(trailingCaption)
            }
            .font(.system(size: 10)).foregroundStyle(theme.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary)
    }

    private func fill(_ kind: KitHeatCell.Kind) -> Color {
        switch kind {
        case .done: theme.green500
        case .missed: theme.elevated
        case .notScheduled: theme.elevated.opacity(0.35)
        case .future: .clear
        }
    }
}

/// One bar of the bar chart
struct KitBar: Hashable {
    enum Tone { case good, fair, low, none }
    /// 0 to 1
    let fraction: Double
    let tone: Tone
    let tooltip: String
}

/// Vertical bars on a common baseline (web: "Weekly completion rate"). The tone sets the colour: green is
/// good, the accent is fair, grey is low.
struct KitBarChart: View {
    @Environment(\.theme) private var theme
    let bars: [KitBar]
    var height: CGFloat = 64
    var leadingCaption: String = ""
    var trailingCaption: String = "This week"
    var summary: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(bars.indices, id: \.self) { i in
                    let bar = bars[i]
                    UnevenRoundedRectangle(topLeadingRadius: 3, topTrailingRadius: 3, style: .continuous)
                        .fill(colour(bar.tone))
                        .frame(height: max(bar.fraction > 0 ? 3 : 0, height * min(max(bar.fraction, 0), 1)))
                        .frame(maxWidth: .infinity)
                        .help(bar.tooltip)
                }
            }
            .frame(height: height, alignment: .bottom)
            HStack {
                Text(leadingCaption)
                Spacer()
                Text(trailingCaption)
            }
            .font(.system(size: 10)).foregroundStyle(theme.textMuted)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary)
    }

    private func colour(_ tone: KitBar.Tone) -> Color {
        switch tone {
        case .good: theme.green500
        case .fair: theme.accent
        case .low: theme.h3
        case .none: theme.surface
        }
    }
}
