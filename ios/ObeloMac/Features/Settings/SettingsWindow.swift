import SwiftUI

/// All the Settings window's stores in one place, so the tabs share them while the window is open
@MainActor @Observable
final class SettingsHub {
    var settings: SettingsStore
    var notifications: NotificationSettingsStore
    var notes: NoteSettingsStore
    var tags: TagManagerStore
    var data: DataTransferStore
    var tokens: ApiTokensStore
    var templates: NoteTemplatesStore
    var calendars: CalendarSourcesStore

    init(api: SettingsAPI, calendars: CalendarSourcesStore = CalendarSourcesStore()) {
        settings = SettingsStore(api: api)
        notifications = NotificationSettingsStore(api: api)
        notes = NoteSettingsStore(api: api)
        tags = TagManagerStore(api: api)
        data = DataTransferStore(api: api)
        tokens = ApiTokensStore(api: api)
        templates = NoteTemplatesStore()
        self.calendars = calendars
    }
    convenience init() { self.init(api: LiveSettingsAPI()) }
}

/// Settings: its own window with a toolbar of tabs, opened with ⌘,. Each card has its
/// own Save button, as on the web; what you change stays in the card until you save.
struct SettingsWindow: View {
    @Environment(AppState.self) private var app
    @Environment(\.theme) private var theme
    @AppStorage("macSettingsTab") private var tab = "account"
    @State private var hub = Self.makeHub()

    private static func makeHub() -> SettingsHub {
        #if DEBUG
        MacDebug.settingsHub()
        #else
        SettingsHub()
        #endif
    }

    var body: some View {
        Group {
            if app.phase == .signedIn {
                TabView(selection: $tab) {
                    AccountPane(hub: hub).tabItem { Label("Account", systemImage: "person.crop.circle") }.tag("account")
                    ModulesPane(hub: hub).tabItem { Label("Modules", systemImage: "square.grid.2x2") }.tag("modules")
                    NotificationsPane(hub: hub).tabItem { Label("Notifications", systemImage: "bell") }.tag("notifications")
                    AppearancePane(hub: hub).tabItem { Label("Appearance", systemImage: "paintpalette") }.tag("appearance")
                    NotesPane(hub: hub).tabItem { Label("Notes", systemImage: "note.text") }.tag("notes")
                    CalendarsPane(hub: hub).tabItem { Label("Calendars", systemImage: "calendar") }.tag("calendars")
                    DashboardPane(hub: hub).tabItem { Label("Dashboard", systemImage: "rectangle.3.group") }.tag("dashboard")
                    TagsPane(hub: hub).tabItem { Label("Tags", systemImage: "tag") }.tag("tags")
                    ShortcutsPane(hub: hub).tabItem { Label("Shortcuts", systemImage: "command") }.tag("shortcuts")
                    DataPane(hub: hub).tabItem { Label("Data", systemImage: "externaldrive") }.tag("data")
                }
            } else {
                KitEmptyState(message: "Sign in to change your settings.")
            }
        }
        .frame(minWidth: 680, idealWidth: 720, minHeight: 520, idealHeight: 680)
        .background(theme.page)
        .onDisappear { Self.putBackUnsavedLook(hub, app) }
        #if DEBUG
        .task {
            // Testing: `-settingsTab appearance` starts on that tab, `-settingsSnapshot settings.png` draws the window and quits
            if let t = UserDefaults.standard.string(forKey: "settingsTab") { tab = t }
            MacDebug.settingsSnapshotIfAsked()
        }
        #endif
    }

    /// Closing the window without saving puts the saved colours back
    static func putBackUnsavedLook(_ hub: SettingsHub, _ app: AppState) {
        guard hub.settings.isAppearanceDirty else { return }
        hub.settings.revertAppearance()
        app.theme = Theme.resolve(app.me?.appearance)
    }
}

/// One tab's page: the server's words in a notice at the top, then the cards
struct SettingsPage<Content: View>: View {
    @Environment(\.theme) private var theme
    @Binding var notice: SettingsNotice?
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let n = notice { KitBanner(kind: n.isError ? .error : .notice, text: n.text) }
                content
            }
            .padding(24)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollEdgeEffectHidden(true, for: .top)
        .background(theme.page)
        .task(id: notice) {
            guard let n = notice else { return }
            try? await Task.sleep(for: .seconds(n.isError ? 10 : 4))
            if notice == n { notice = nil }
        }
    }
}

/// A card with a title, a line of help and its content (web: the bg-gray-900 cards on the settings page)
struct SettingsCard<Content: View>: View {
    @Environment(\.theme) private var theme
    let title: String
    var detail: String?
    var danger = false
    @ViewBuilder var content: Content

    var body: some View {
        KitCard {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(danger ? theme.red400 : theme.text100)
                        .accessibilityAddTraits(.isHeader)
                    if let detail { Text(detail).font(.system(size: 12)).foregroundStyle(theme.textMuted).fixedSize(horizontal: false, vertical: true) }
                }
                content
            }
            .padding(20)
        }
        .overlay(danger ? RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(theme.red800.opacity(0.5)) : nil)
    }
}
