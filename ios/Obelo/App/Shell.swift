import WidgetKit
import SwiftUI

// The signed-in app frame: a top bar with the logo, page title, search and avatar; a bottom bar
// plus "More", which opens a sheet with every other module in a 4-column grid.

/// The bottom bar from the redesign plan: Today, Tasks, Notes and
/// Routines, then More. Only modules the user has switched on appear in the bar; the rest go in More.
enum BottomBar {
    static let order = ["dashboard", "tasks", "notes", "routines"]

    static func keys(enabled: [String]) -> [String] {
        order.filter { enabled.contains($0) }
    }
}

enum Route: Hashable {
    case module(String)
    case task(Int)
    case reminder(Int)
    case routine(Int)
    case note(Int)
    case list(Int)
    case event(CalendarEvent)
    case eventID(Int)
    case search
}

struct MainShell: View {
    @Environment(AppState.self) private var app
    @Environment(Navigator.self) private var nav
    @Environment(\.theme) private var theme
    @State private var selected = "dashboard"
    @State private var paths: [String: NavigationPath] = [:]
    @State private var showMore = false
    @State private var toast = Toast()
    #if DEBUG
    @State private var sharePreview = false
    @State private var widgetPreview = false
    @State private var drawPreview = false
    #endif

    private var navKeys: [String] { BottomBar.keys(enabled: app.me?.modules.map(\.key) ?? ["dashboard"]) }
    private var overflow: [String] {
        (app.me?.modules.map(\.key) ?? []).filter { !navKeys.contains($0) } + ["help"]
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // One navigation stack per root module, kept alive while switching
            ForEach(Array(Set(navKeys + [selected])), id: \.self) { key in
                stack(for: key)
                    .opacity(key == selected ? 1 : 0)
                    .allowsHitTesting(key == selected)
            }
            BottomNav(keys: navKeys, selected: selected, moreActive: !navKeys.contains(selected)) { key in
                if key == selected {
                    paths[key] = NavigationPath() // tap again: back to the root, like a web nav link
                } else {
                    selected = key
                }
            } more: {
                showMore = true
            }
            .ignoresSafeArea(.keyboard, edges: .bottom) // stays put behind the keyboard
            ToastOverlay(toast: toast)
        }
        .environment(toast)
        // Keyboard shortcuts (⌘1…, ⌘F, ⌘N) go through the Navigator, as in the sidebar layout
        .onChange(of: selected) { _, key in if nav.selected != key { nav.selected = key } }
        .onChange(of: nav.selected) { _, key in
            guard key != selected else { return }
            showMore = false
            if key == "search" {
                // Search opens over the current tab, which stays selected
                paths[selected, default: NavigationPath()].append(Route.search)
                nav.selected = selected
            } else {
                selected = key
            }
        }
        .onAppear { nav.selected = selected }
        .onOpenURL { url in
            // From the widget: obelo://open/today, obelo://open/task/12, …/reminder/3, …/routine/5
            guard url.scheme == "obelo", url.host() == "open" else { return }
            let parts = url.pathComponents.filter { $0 != "/" }
            showMore = false
            selected = "dashboard"
            var path = NavigationPath()
            if parts.count == 2, let id = Int(parts[1]) {
                switch parts[0] {
                case "task": path.append(Route.task(id))
                case "reminder": path.append(Route.reminder(id))
                case "routine": path.append(Route.routine(id))
                default: break
                }
            }
            paths["dashboard"] = path
        }
        .sheet(isPresented: $showMore) {
            MoreSheet(keys: overflow, selected: selected) { key in
                showMore = false
                selected = key
            }
            .presentationDetents([.height(CGFloat(80 + ((overflow.count + 3) / 4) * 92))])
            .presentationDragIndicator(.visible)
            .presentationBackground(theme.surface)
            .environment(\.theme, theme)
        }
        #if DEBUG
        #if os(iOS)
        .sheet(isPresented: $widgetPreview) { WidgetPreview() }
        #endif
        .fullScreen(isPresented: $drawPreview) {
            // Simulator testing of the drawing editor with a sample drawing made at another width
            DrawingEditor(doc: DrawingDoc(w: 720, h: 2400, strokes: [
                .init(color: "#93c5fd", width: 3, eraser: false, points: [.init(x: 60, y: 120, p: 0.5), .init(x: 300, y: 260, p: 0.8), .init(x: 600, y: 140, p: 0.5)]),
                .init(color: "#fca5a5", width: 6, eraser: false, points: [.init(x: 100, y: 500, p: 0.5), .init(x: 620, y: 520, p: 0.5)]),
                .init(color: "#000", width: 20, eraser: true, points: [.init(x: 360, y: 400, p: 0.5), .init(x: 360, y: 620, p: 0.5)]),
            ])) { _ in drawPreview = false }
        }
        .sheet(isPresented: $sharePreview) {
            // Simulator testing of the share extension's UI: `-route share`
            ShareView(item: SharedItem(url: "https://developer.apple.com/documentation/swiftui",
                                       title: "SwiftUI | Apple Developer Documentation", text: nil)) { _ in sharePreview = false }
                .environment(\.theme, theme)
        }
        .onAppear {
            // Simulator testing: `-startTab tasks` / `-route note:3` open a screen on launch
            let d = UserDefaults.standard
            if let tab = d.string(forKey: "startTab") { selected = tab }
            if let route = d.string(forKey: "route") {
                let parts = route.split(separator: ":").map(String.init)
                let id = Int(parts.last ?? "") ?? 0
                let r: Route? = switch parts.first {
                case "task": .task(id)
                case "reminder": .reminder(id)
                case "routine": .routine(id)
                case "note": .note(id)
                case "list": .list(id)
                case "event": .eventID(id)
                case "module": .module(parts.last ?? "")
                case "search": .search
                case "more": nil
                default: nil
                }
                if parts.first == "more" { showMore = true }
                if parts.first == "share" { sharePreview = true }
                if parts.first == "widget" { widgetPreview = true }
                if parts.first == "draw" { drawPreview = true }
                if let r { var p = NavigationPath(); p.append(r); paths[selected] = p }
            }
        }
        #endif
    }

    private func stack(for key: String) -> some View {
        NavigationStack(path: Binding(get: { paths[key] ?? NavigationPath() }, set: { paths[key] = $0 })) {
            ModuleScreen(key: key)
                .safeAreaInset(edge: .top, spacing: 0) { TopBar(title: ModuleMeta.of(key).label) }
                .navigationBarVisibility(.hidden)
                .keyboardDoneButton()
                .navigationDestination(for: Route.self) { route in
                    RouteView(route: route)
                }
        }
        .tint(theme.text400)
    }
}

/// Every screen reachable through navigation
struct RouteView: View {
    let route: Route
    var body: some View {
        Group {
        switch route {
        case .module(let key): ModuleScreen(key: key, pushed: true)
        case .task(let id): TaskDetailView(id: id)
        case .reminder(let id): ReminderDetailView(id: id)
        case .routine(let id): RoutineDetailView(id: id)
        case .note(let id): NoteDetailView(id: id)
        case .list(let id): ListDetailView(id: id)
        case .event(let event): EventDetailView(event: event)
        case .eventID(let id): EventLoader(id: id)
        case .search: SearchView()
        }
        }
        .keyboardDoneButton()
    }
}

/// A module's main screen
struct ModuleScreen: View {
    @Environment(\.theme) private var theme
    let key: String
    var pushed = false

    var body: some View {
        Group {
            switch key {
            case "dashboard": TodayView()
            case "tasks": TasksView()
            case "reminders": RemindersView()
            case "routines": RoutinesView()
            case "notes": NotesView()
            case "lists": ListsView()
            case "bookmarks": BookmarksView()
            case "calendar": CalendarView()
            case "capture": CaptureView()
            case "settings": SettingsView()
            case "analytics": AnalyticsView()
            case "ai": AIChatView()
            case "help": HelpView()
            default: WebOnlyView(key: key)
            }
        }
        .modifier(PushedChrome(pushed: pushed, title: ModuleMeta.of(key).label))
    }

    private struct PushedChrome: ViewModifier {
        @Environment(\.theme) private var theme
        let pushed: Bool
        let title: String
        func body(content: Content) -> some View {
            if pushed { content.themedNavBar(theme, title: title).navigationBarVisibility(.visible) } else { content }
        }
    }
}

// ── Top bar ───────────────────────────────────────────────────────────────────

struct TopBar: View {
    @Environment(AppState.self) private var app
    @Environment(\.theme) private var theme
    let title: String

    var body: some View {
        HStack {
            Text("Obelo").font(.system(size: 19, weight: .bold)).foregroundStyle(theme.textPrimary)
            Spacer()
            HStack(spacing: 12) {
                Text(title).font(.system(size: 14)).foregroundStyle(theme.text400)
                NavigationLink(value: Route.search) {
                    Image(systemName: "magnifyingglass").font(.system(size: 17)).foregroundStyle(theme.textMuted)
                }
                .accessibilityLabel("Search")
                NavigationLink(value: Route.module("settings")) {
                    AvatarView(url: app.me?.avatarUrl, name: app.me?.user.displayName ?? "?", size: 28)
                }
                .accessibilityLabel("Settings")
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(theme.surface)
        .overlay(alignment: .bottom) { RowDivider() }
    }
}

// ── Bottom nav ────────────────────────────────────────────────────────────────

struct BottomNav: View {
    @Environment(\.theme) private var theme
    let keys: [String]
    let selected: String
    let moreActive: Bool
    let select: (String) -> Void
    let more: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(keys, id: \.self) { key in
                item(ModuleMeta.of(key), active: key == selected) { select(key) }
            }
            item(ModuleMeta(key: "more", label: "More", icon: "line.3.horizontal"), active: moreActive, action: more)
        }
        .padding(.horizontal, 8).padding(.top, 8).padding(.bottom, 4)
        .background(theme.surface.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { RowDivider() }
    }

    private func item(_ meta: ModuleMeta, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: meta.icon).font(.system(size: 19)).frame(height: 22)
                Text(meta.label).font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(active ? theme.accentText : theme.textMuted)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}

struct MoreSheet: View {
    @Environment(\.theme) private var theme
    let keys: [String]
    let selected: String
    let select: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("MORE")
                .font(.system(size: 12, weight: .semibold)).tracking(0.6)
                .foregroundStyle(theme.text400)
                .padding(.horizontal, 16).padding(.top, 24).padding(.bottom, 12)
            RowDivider()
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 4), spacing: 4) {
                ForEach(keys, id: \.self) { key in
                    let meta = ModuleMeta.of(key)
                    let active = key == selected
                    Button { select(key) } label: {
                        VStack(spacing: 6) {
                            Image(systemName: meta.icon).font(.system(size: 20))
                            Text(meta.label).font(.system(size: 10, weight: .medium)).multilineTextAlignment(.center)
                        }
                        .foregroundStyle(active ? theme.accentText : theme.text400)
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(active ? theme.accent.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
            Spacer(minLength: 0)
        }
    }
}

/// Modules that haven't been built natively yet open on the web
struct WebOnlyView: View {
    @Environment(\.theme) private var theme
    @Environment(\.openURL) private var openURL
    let key: String

    private var path: String { key == "help" ? "/help" : "/\(key)" }

    var body: some View {
        Page {
            PageHeader(title: ModuleMeta.of(key).label, pageName: true)
            Card(padding: 20) {
                VStack(alignment: .leading, spacing: 14) {
                    Image(systemName: ModuleMeta.of(key).icon).font(.system(size: 28)).foregroundStyle(theme.accentText)
                    Text("\(ModuleMeta.of(key).label) is on the web for now")
                        .font(.system(size: 16, weight: .semibold)).foregroundStyle(theme.textPrimary)
                    Text("This part of Obelo hasn't come to the app yet. You can open it in your browser.")
                        .font(.system(size: 14)).foregroundStyle(theme.text400)
                    PrimaryButton(title: "Open in browser", systemImage: "safari") {
                        openURL(APIClient.shared.url(path))
                    }
                }
            }
        }
    }
}

#if DEBUG && os(iOS)
/// Simulator testing of the widget's views at their real sizes (iPhone 17 Pro points)
private struct WidgetPreview: View {
    @State private var entry: TodayEntry?
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if let entry {
                    tile(entry, .systemSmall, CGSize(width: 170, height: 170))
                    tile(entry, .systemMedium, CGSize(width: 364, height: 170))
                    tile(entry, .systemLarge, CGSize(width: 364, height: 382))
                }
            }
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity)
        }
        .background(Color(hex: "#3a4a6a"))
        .task { entry = await TodayProvider.load() }
    }

    private func tile(_ e: TodayEntry, _ family: WidgetFamily, _ size: CGSize) -> some View {
        TodayWidgetView(entry: e, familyOverride: family)
            .padding(16)
            .frame(width: size.width, height: size.height)
            .background(Theme.resolve(e.appearance).surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}
#endif
