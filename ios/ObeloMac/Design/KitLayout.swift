import SwiftUI

// The Mac design kit: layout pieces. Ported from the web's page patterns (partials/page-heading.ejs,
// empty-state.ejs, the card classes). Every type is prefixed Kit so it can't be confused with the
// iPhone app's components, which the Mac stops compiling in Milestone 11.

/// Page widths from Phase 2
enum KitWidth {
    static let list: CGFloat = 768       // max-w-3xl
    static let calendar: CGFloat = 1024  // max-w-5xl
    static let form: CGFloat = 576       // max-w-xl
    static let chat: CGFloat = 672       // max-w-2xl
}

/// The page column: content centred, capped at the page's width, on the page colour
struct KitPage<Content: View>: View {
    @Environment(\.theme) private var theme
    var width: CGFloat = KitWidth.list
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            content
                .frame(maxWidth: width, alignment: .leading)
                .padding(24)
                .frame(maxWidth: .infinity)
        }
        .scrollEdgeEffectHidden(true, for: .top)
        .background(theme.page)
    }
}

/// Page name and one line of muted description, with room for actions on the right
struct KitPageHeading<Trailing: View>: View {
    @Environment(\.theme) private var theme
    let title: String
    let description: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 24, weight: .bold)).foregroundStyle(theme.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                if !description.isEmpty { Text(description).font(.system(size: 14)).foregroundStyle(theme.textMuted) }
            }
            Spacer(minLength: 12)
            trailing
        }
    }
}

extension KitPageHeading where Trailing == EmptyView {
    init(title: String, description: String) {
        self.init(title: title, description: description) { EmptyView() }
    }
}

/// A card: surface colour, hairline border, rounded corners (web: bg-gray-900 border border-gray-800 rounded-xl)
struct KitCard<Content: View>: View {
    @Environment(\.theme) private var theme
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(theme.border1))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// The title strip at the top of a card, with room for a link or button on the right.
/// `uppercase` is the small grey label style the dashboard cards use.
struct KitCardHeader<Trailing: View>: View {
    @Environment(\.theme) private var theme
    let title: String
    var detail: String?
    var uppercase = false
    var badge: String?
    var badgeTone: KitBadge.Tone = .neutral
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 8) {
            if uppercase {
                Text(title.uppercased()).font(.system(size: 11, weight: .semibold)).tracking(0.6)
                    .foregroundStyle(theme.textMuted)
                    .accessibilityLabel(title).accessibilityAddTraits(.isHeader)
            } else {
                Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(theme.text100)
                    .accessibilityAddTraits(.isHeader)
            }
            if let badge { KitBadge(text: badge, tone: badgeTone) }
            if let detail { Text(detail).font(.system(size: 12)).foregroundStyle(theme.textMuted) }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.border1).frame(height: 1) }
    }
}

extension KitCardHeader where Trailing == EmptyView {
    init(title: String, detail: String? = nil, uppercase: Bool = false, badge: String? = nil, badgeTone: KitBadge.Tone = .neutral) {
        self.init(title: title, detail: detail, uppercase: uppercase, badge: badge, badgeTone: badgeTone) { EmptyView() }
    }
}

/// A line of muted text inside a card ("No events today."), optionally followed by a link
struct KitCardMessage<Accessory: View>: View {
    @Environment(\.theme) private var theme
    let text: String
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(spacing: 6) {
            Text(text).font(.system(size: 14)).italic().foregroundStyle(theme.textMuted)
            accessory
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
    }
}

extension KitCardMessage where Accessory == EmptyView {
    init(_ text: String) { self.init(text: text) { EmptyView() } }
}

/// A thin heading row between groups of rows inside a card (Morning, Afternoon, Upcoming's days)
struct KitGroupHeaderRow: View {
    @Environment(\.theme) private var theme
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold)).tracking(1)
            .foregroundStyle(theme.textMuted)
            .padding(.horizontal, 16).padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.elevated.opacity(0.5))
            .overlay(alignment: .bottom) { KitDivider() }
            .accessibilityAddTraits(.isHeader)
    }
}

/// The small upper-case label above a group of fields or rows
struct KitGroupLabel: View {
    @Environment(\.theme) private var theme
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold)).tracking(0.6)
            .foregroundStyle(theme.textMuted)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A hairline between rows
struct KitDivider: View {
    @Environment(\.theme) private var theme
    var body: some View { Rectangle().fill(theme.border1).frame(height: 1) }
}

/// One line of muted text and, at most, one button (web: partials/empty-state.ejs)
struct KitEmptyState: View {
    @Environment(\.theme) private var theme
    let message: String
    var actionLabel: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Text(message).font(.system(size: 14)).foregroundStyle(theme.textMuted)
            if let actionLabel, let action {
                Button(actionLabel, action: action).buttonStyle(KitButtonStyle(.secondary))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .accessibilityElement(children: .combine)
    }
}
