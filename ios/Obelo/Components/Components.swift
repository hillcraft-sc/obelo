import SwiftUI

// Building blocks that reproduce the web app's recurring Tailwind patterns.

// ── Card: rounded-xl bg-gray-900 border border-gray-800 overflow-hidden ──────────

struct Card<Content: View>: View {
    @Environment(\.theme) private var theme
    var padding: CGFloat = 0
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.border1, lineWidth: 1))
    }
}

/// Card header: "px-5 pt-4 pb-3 border-b" with an uppercase tracking-wider title and an optional link
struct CardHeader<Trailing: View>: View {
    @Environment(\.theme) private var theme
    let title: String
    var badge: String? = nil
    var badgeWarn = false
    var note: String? = nil
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center) {
            HStack(spacing: 8) {
                Text(title.uppercased())
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(theme.textMuted)
                if let note {
                    Text(note).font(.system(size: 10)).foregroundStyle(theme.textMuted)
                }
                if let badge {
                    Text(badge)
                        .font(.system(size: 10))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(badgeWarn ? theme.amber900.opacity(0.5) : theme.elevated, in: Capsule())
                        .foregroundStyle(badgeWarn ? theme.amber400 : theme.text400)
                }
            }
            Spacer()
            trailing
        }
        .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 12)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.border1).frame(height: 1) }
    }
}

extension CardHeader where Trailing == EmptyView {
    init(title: String, badge: String? = nil, badgeWarn: Bool = false, note: String? = nil) {
        self.init(title: title, badge: badge, badgeWarn: badgeWarn, note: note) { EmptyView() }
    }
}

/// "text-xs text-gray-600 hover:text-gray-400" link text, e.g. "All tasks →"
struct HeaderLink: View {
    @Environment(\.theme) private var theme
    let title: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 12)).foregroundStyle(theme.textMuted)
        }
        .buttonStyle(.plain)
    }
}

/// A row divider: border-b border-gray-800
struct RowDivider: View {
    @Environment(\.theme) private var theme
    var body: some View { Rectangle().fill(theme.border1).frame(height: 1) }
}

/// Group label inside a card: "px-5 py-1.5 bg-gray-800/30 … text-[10px] uppercase tracking-widest"
struct GroupLabel: View {
    @Environment(\.theme) private var theme
    let title: String
    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(1.2)
            .foregroundStyle(theme.textMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16).padding(.vertical, 6)
            .background(theme.elevated.opacity(0.5))
            .overlay(alignment: .bottom) { RowDivider() }
    }
}

// ── Page scaffolding ──────────────────────────────────────────────────────────

/// Page heading (Phase 2 pattern, partials/page-heading.ejs): the page name, one line of muted
/// description, and one primary action on the right. On iPhone the top bar already shows the page
/// name, so a module's heading leaves it out (`pageName: true`) and shows only the description.
/// Headings that aren't the page name (a list's title, a date range) always show.
struct PageHeader<Trailing: View>: View {
    @Environment(\.theme) private var theme
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif
    let title: String
    var subtitle: String? = nil
    var pageName = false
    @ViewBuilder var trailing: Trailing

    /// The Mac and wide iPad layouts have a sidebar and no top bar, so the heading shows the name
    private var showsTitle: Bool {
        #if os(iOS)
        !(pageName && sizeClass == .compact)
        #else
        true
        #endif
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                if showsTitle {
                    Text(title).font(.system(size: 24, weight: .bold)).foregroundStyle(theme.textPrimary)
                }
                if let subtitle {
                    Text(subtitle).font(.system(size: 14)).foregroundStyle(theme.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            trailing.fixedSize()
        }
    }
}

extension PageHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil, pageName: Bool = false) {
        self.init(title: title, subtitle: subtitle, pageName: pageName) { EmptyView() }
    }
}

/// "bg-indigo-600 hover:bg-indigo-500 text-white text-sm font-medium rounded-lg" button
struct PrimaryButton: View {
    @Environment(\.theme) private var theme
    let title: String
    var systemImage: String? = nil
    var fullWidth = false
    var busy = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if busy { ProgressView().tint(theme.onAccent).controlSize(.small) }
                else if let systemImage { Image(systemName: systemImage).font(.system(size: 13, weight: .semibold)) }
                Text(title).font(.system(size: 14, weight: .medium))
            }
            .foregroundStyle(theme.onAccent)
            .padding(.horizontal, 14).padding(.vertical, 9)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .background(theme.accent, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .disabled(busy)
    }
}

/// "bg-gray-800 border border-gray-700 text-gray-300" secondary button
struct SecondaryButton: View {
    @Environment(\.theme) private var theme
    let title: String
    var systemImage: String? = nil
    var tint: Color? = nil
    var active = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage { Image(systemName: systemImage).font(.system(size: 13)) }
                Text(title).font(.system(size: 14, weight: .medium))
            }
            .foregroundStyle(tint ?? theme.text400)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(active ? (tint ?? theme.accent).opacity(0.15) : theme.elevated, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(active ? (tint ?? theme.accent).opacity(0.6) : theme.border2, lineWidth: 1))
        }
        .buttonStyle(PressableStyle())
    }
}

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.75 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Section tabs within a page (Phase 2 pattern, partials/tabs.ejs): underlined tabs on a bottom rule,
/// active = "bg-gray-800 text-white border-b-2 border-indigo-500"
struct SectionTab: Identifiable {
    let key: String
    let label: String
    var badge: Int? = nil
    var warn = false
    var id: String { key }
}

struct SectionTabs: View {
    @Environment(\.theme) private var theme
    let tabs: [SectionTab]
    @Binding var selection: String

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(tabs) { tab in
                    let active = tab.key == selection
                    Button {
                        withAnimation(.snappy(duration: 0.2)) { selection = tab.key }
                    } label: {
                        HStack(spacing: 6) {
                            Text(tab.label).font(.system(size: 14, weight: active ? .medium : .regular))
                            if let badge = tab.badge, badge > 0 {
                                Text("\(badge)")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(tab.warn ? theme.red500 : (active ? theme.accentHover : theme.h2), in: Capsule())
                            }
                        }
                        .foregroundStyle(active ? theme.textPrimary : theme.textMuted)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(active ? theme.elevated : .clear,
                                    in: UnevenRoundedRectangle(topLeadingRadius: 8, topTrailingRadius: 8, style: .continuous))
                        .overlay(alignment: .bottom) {
                            if active { Rectangle().fill(theme.accentHover).frame(height: 2) }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(active ? .isSelected : [])
                    .id(tab.key)
                }
            }
        }
        .background(alignment: .bottom) { RowDivider() }
        // Keep the selected tab in view (it may start off-screen, or be chosen from elsewhere)
        .onAppear { proxy.scrollTo(selection, anchor: .center) }
        .onChange(of: selection) { _, key in withAnimation { proxy.scrollTo(key, anchor: .center) } }
        }
    }
}

/// Tag filter chips: "#tag" rounded-full, active = bg-indigo-600
struct TagFilter: View {
    @Environment(\.theme) private var theme
    let tags: [String]
    @Binding var selected: String?

    var body: some View {
        if !tags.isEmpty {
            FlowLayout(spacing: 6) {
                ForEach(tags, id: \.self) { tag in
                    let active = selected == tag
                    Button {
                        selected = active ? nil : tag
                    } label: {
                        Text("#\(tag)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(active ? theme.onAccent : theme.textMuted)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(active ? theme.accent : theme.elevated, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

/// Inline tag pill: "px-1.5 py-0.5 rounded text-[10px] bg-gray-800 text-gray-600"
struct TagPill: View {
    @Environment(\.theme) private var theme
    let tag: String
    var body: some View {
        Text("#\(tag)")
            .font(.system(size: 10))
            .foregroundStyle(theme.textMuted)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(theme.elevated, in: RoundedRectangle(cornerRadius: 4))
    }
}

/// Small coloured badge: e.g. "stale 40d", "Pinned"
struct Badge: View {
    let text: String
    let fg: Color
    let bg: Color
    var border: Color? = nil
    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(fg)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(bg, in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(border ?? .clear, lineWidth: 1))
    }
}

// ── Inputs ───────────────────────────────────────────────────────────────────

/// "px-3.5 py-2.5 rounded-lg bg-gray-800 border border-gray-700 text-gray-100 placeholder-gray-600 text-sm"
struct ThemedField: View {
    @Environment(\.theme) private var theme
    let placeholder: String
    @Binding var text: String
    var axis: Axis = .horizontal
    var submit: (() -> Void)? = nil
    @FocusState private var focused: Bool

    var body: some View {
        TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(theme.placeholder), axis: axis)
            .font(.system(size: 15))
            .foregroundStyle(theme.text100)
            .focused($focused)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(theme.isDark ? theme.elevated : theme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(focused ? theme.accent : theme.border2, lineWidth: focused ? 2 : 1)
            )
            .onSubmit { submit?() }
            .submitLabel(submit == nil ? .return : .done)
    }
}

/// Form label: "block text-sm font-medium text-gray-300 mb-1.5"
struct FieldLabel: View {
    @Environment(\.theme) private var theme
    let text: String
    var body: some View {
        Text(text).font(.system(size: 14, weight: .medium)).foregroundStyle(theme.text300)
    }
}

struct FormSection<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            FieldLabel(text: label)
            content
        }
    }
}

/// A themed menu picker that looks like the web's <select>
struct SelectField<Value: Hashable>: View {
    @Environment(\.theme) private var theme
    let options: [(Value, String)]
    @Binding var selection: Value

    var body: some View {
        Menu {
            ForEach(options, id: \.0) { value, label in
                Button {
                    selection = value
                } label: {
                    if value == selection { Label(label, systemImage: "checkmark") } else { Text(label) }
                }
            }
        } label: {
            HStack {
                Text(options.first { $0.0 == selection }?.1 ?? "")
                    .font(.system(size: 15)).foregroundStyle(theme.text100)
                Spacer()
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 11)).foregroundStyle(theme.textMuted)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(theme.isDark ? theme.elevated : theme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(theme.border2, lineWidth: 1))
        }
    }
}

/// Error / success banners: "px-4 py-3 rounded-lg bg-red-950 border border-red-800 text-red-300 text-sm"
struct Banner: View {
    @Environment(\.theme) private var theme
    enum Kind { case error, success, warning }
    let kind: Kind
    let text: String

    var body: some View {
        let (fg, bg, bd): (Color, Color, Color) = switch kind {
        case .error: (theme.red300, theme.red950, theme.red800)
        case .success: (theme.green300, theme.green950, theme.green800)
        case .warning: (theme.amber300, theme.amber950.opacity(0.6), theme.amber900)
        }
        Text(text)
            .font(.system(size: 14))
            .foregroundStyle(fg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(bg, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(bd, lineWidth: 1))
    }
}

/// Empty state (Phase 2 pattern, partials/empty-state.ejs): a centred line of muted text, plus at
/// most one button that starts the thing ("New task") or clears a filter ("Clear filter").
struct EmptyAction {
    let label: String
    let action: () -> Void
}

struct EmptyRow: View {
    @Environment(\.theme) private var theme
    let text: String
    var action: EmptyAction? = nil

    var body: some View {
        VStack(spacing: 12) {
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(theme.textMuted)
                .multilineTextAlignment(.center)
            if let action {
                Button(action: action.action) {
                    Text(action.label)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(theme.text200)
                        .padding(.horizontal, 14).padding(.vertical, 6)
                        .background(theme.elevated, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(theme.border2, lineWidth: 1))
                }
                .buttonStyle(PressableStyle())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
        .padding(.horizontal, 20)
    }
}

// ── Row controls ─────────────────────────────────────────────────────────────

/// The round completion button: "w-5 h-5 rounded-full border-2"
struct CompleteCircle: View {
    @Environment(\.theme) private var theme
    var done = false
    var ring: Color? = nil
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.light()
            action()
        } label: {
            ZStack {
                Circle()
                    .stroke(done ? theme.green500 : (ring ?? theme.border3), lineWidth: 2)
                    .background(Circle().fill(done ? theme.green500.opacity(0.2) : .clear))
                if done {
                    Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy)).foregroundStyle(theme.green400)
                }
            }
            .frame(width: 20, height: 20)
            .padding(8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(-8)
        .accessibilityLabel(done ? "Mark incomplete" : "Mark complete")
    }
}

/// The routine checkbox: "w-5 h-5 rounded-md border-2"
struct CompleteSquare: View {
    @Environment(\.theme) private var theme
    var done: Bool
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.light()
            action()
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(done ? theme.green500 : (enabled ? theme.border3 : theme.border2),
                                  style: StrokeStyle(lineWidth: 2, dash: enabled || done ? [] : [3, 2]))
                    .background(RoundedRectangle(cornerRadius: 5).fill(done ? theme.green500.opacity(0.2) : .clear))
                if done {
                    Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy)).foregroundStyle(theme.green400)
                }
            }
            .frame(width: 20, height: 20)
            .padding(8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(-8)
        .disabled(!enabled && !done)
        .accessibilityLabel(done ? "Mark incomplete" : "Mark complete")
    }
}

/// Priority chevrons, like PRIORITY_ICON in routes/tasks.js (1–3 stacked chevrons)
struct PriorityIcon: View {
    @Environment(\.theme) private var theme
    let priority: String

    var body: some View {
        let count = ["low": 1, "medium": 2, "high": 3][priority] ?? 0
        ChevronStack(count: count)
            .stroke(theme.text400, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            .frame(width: 14, height: 14)
            .opacity(count == 0 ? 0 : 1)
            .accessibilityLabel("\(Fmt.priorityLabel(priority)) priority")
    }

    nonisolated struct ChevronStack: Shape {
        let count: Int
        func path(in rect: CGRect) -> Path {
            var p = Path()
            guard count > 0 else { return p }
            let s = rect.width / 24
            // Heroicons chevron-up / double / triple geometry
            let tops: [CGFloat] = switch count {
            case 1: [8.25]
            case 2: [5.25, 11.25]
            default: [1.5, 7.5, 13.5]
            }
            for top in tops {
                p.move(to: CGPoint(x: 4.5 * s, y: (top + 7.5) * s))
                p.addLine(to: CGPoint(x: 12 * s, y: top * s))
                p.addLine(to: CGPoint(x: 19.5 * s, y: (top + 7.5) * s))
            }
            return p
        }
    }
}

struct Dot: View {
    let color: Color
    var size: CGFloat = 8
    var body: some View { Circle().fill(color).frame(width: size, height: size) }
}

// ── Layout ───────────────────────────────────────────────────────────────────

/// Wrapping horizontal layout (flex-wrap)
nonisolated struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0; y += rowHeight + spacing; rowHeight = 0
            }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: min(maxX, width), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        // Wrap at the width sizeThatFits measured with, not at bounds (which can be narrower: the
        // layout reports its widest row as its width). Wrapping at bounds could add a row nobody measured.
        let limit = bounds.minX + (proposal.width ?? bounds.width)
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > limit {
                x = bounds.minX; y += rowHeight + spacing; rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// Standard scrolling page: themed background, pull to refresh, and the Phase 2 page width: every
/// list page is the web's max-w-3xl (768pt). Calendar is wider (5xl) and forms narrower (xl).
struct Page<Content: View>: View {
    @Environment(\.theme) private var theme
    var maxWidth: CGFloat = 768
    var refresh: (() async -> Void)? = nil
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) { content }
                .frame(maxWidth: maxWidth)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 100)
        }
        .scrollDismissesKeyboard(.immediately)
        .background(theme.page)
        .refreshable { await refresh?() }
        #if DEBUG
        // Simulator screenshots: `-scrollY 0.5` starts pages scrolled halfway
        .defaultScrollAnchor(UserDefaults.standard.object(forKey: "scrollY") == nil ? nil
            : UnitPoint(x: 0.5, y: UserDefaults.standard.double(forKey: "scrollY")))
        #endif
    }
}

/// Loading / error wrapper for a screen's first load
struct Loadable<Value, Content: View>: View {
    @Environment(\.theme) private var theme
    let value: Value?
    let error: String?
    let retry: () async -> Void
    @ViewBuilder var content: (Value) -> Content

    var body: some View {
        if let value {
            content(value)
        } else if let error {
            VStack(spacing: 14) {
                Banner(kind: .error, text: error)
                SecondaryButton(title: "Try again", systemImage: "arrow.clockwise") { Task { await retry() } }
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(theme.page)
        } else {
            ProgressView()
                .tint(theme.textMuted)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(theme.page)
        }
    }
}

extension View {
    /// Themed navigation bar for pushed detail screens (the web's "‹ Back" link row)
    func themedNavBar(_ theme: Theme, title: String = "") -> some View {
        self
            .navigationTitle(title)
            .inlineNavigationTitle()
            #if os(iOS)
            .toolbarBackground(theme.page, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(theme.colorScheme, for: .navigationBar)
            #endif
    }
}

