import SwiftUI

/// Settings ▸ Modules: which modules are on, and their order (the sidebar follows it)
struct ModulesPane: View {
    @Environment(AppState.self) private var app
    @Bindable var hub: SettingsHub

    private var items: [KitSortItem] {
        let s = hub.settings
        return s.modules.sorted { SidebarGroups.sortRank($0.key) < SidebarGroups.sortRank($1.key) }.map { KitSortItem(id: $0.key, title: $0.label, detail: nil, isOn: $0.enabled, isFixed: $0.alwaysEnabled) }
    }

    var body: some View {
        SettingsPage(notice: $hub.settings.notice) {
            SettingsCard(title: "Modules", detail: "Switch modules on or off. The sidebar groups them in a fixed order; the phone's bottom bar order is set on iPhone.") {
                if hub.settings.loaded {
                    KitSortList(items: items, reorderable: false, onToggle: { hub.settings.toggleModule($0) })
                    HStack(spacing: 12) {
                        Button("Save modules") {
                            Task { if await hub.settings.saveModules() { try? await app.loadMe() } }
                        }
                        .buttonStyle(KitButtonStyle(.primary)).disabled(!hub.settings.isModulesDirty)
                        if hub.settings.isModulesDirty { KitLinkButton(title: "Undo changes", size: 12, tone: .muted) { hub.settings.revertModules() } }
                    }
                } else {
                    KitEmptyState(message: "Loading…")
                }
            }
        }
        .task { if !hub.settings.loaded { await hub.settings.load() } }
    }
}

/// Settings ▸ Dashboard: which Today cards show, and their order
struct DashboardPane: View {
    @Environment(AppState.self) private var app
    @Bindable var hub: SettingsHub

    private var items: [KitSortItem] {
        hub.settings.widgets.map { KitSortItem(id: $0.key, title: $0.label, detail: $0.description, isOn: $0.enabled) }
    }

    var body: some View {
        SettingsPage(notice: $hub.settings.notice) {
            SettingsCard(title: "Dashboard Widgets", detail: "Drag to reorder. Toggle to show or hide.") {
                if hub.settings.loaded {
                    KitSortList(items: items, onMove: { hub.settings.moveWidget($0, by: $1) }, onToggle: { hub.settings.toggleWidget($0) })
                    HStack(spacing: 12) {
                        Button("Save dashboard") {
                            Task { if await hub.settings.saveDashboard() { app.dataChanged() } }
                        }
                        .buttonStyle(KitButtonStyle(.primary)).disabled(!hub.settings.isDashboardDirty)
                    }
                } else {
                    KitEmptyState(message: "Loading…")
                }
            }
        }
        .task { if !hub.settings.loaded { await hub.settings.load() } }
    }
}

/// Settings ▸ Appearance: the theme (the whole app changes as you choose; Save keeps it), custom colours, status colours
struct AppearancePane: View {
    @Environment(AppState.self) private var app
    @Environment(\.theme) private var theme
    @Bindable var hub: SettingsHub

    private var look: SettingsData.Look { hub.settings.look }

    private func resolved(_ id: String) -> Theme {
        Theme.resolve(Appearance(theme: id, isDark: false, customAccent: look.customAccent, customBase: look.customBase, statusColors: look.statusColors))
    }

    private func preview() {
        withAnimation(.easeInOut(duration: 0.2)) { app.theme = resolved(look.theme) }
    }

    var body: some View {
        SettingsPage(notice: $hub.settings.notice) {
            SettingsCard(title: "Theme", detail: "Choose a color scheme for the app") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
                    ForEach(Theme.builtIn, id: \.id) { t in
                        KitThemeCard(name: Theme.labels[t.id]?.label ?? t.id, detail: Theme.labels[t.id]?.desc ?? "", preview: resolved(t.id),
                                     isSelected: look.theme == t.id) { choose(t.id) }
                    }
                    KitThemeCard(name: "Custom", detail: "Your accent colour", preview: resolved("custom"), isSelected: look.theme == "custom") { choose("custom") }
                }
                if look.theme == "custom" {
                    KitDivider()
                    KitFieldLabel(text: "Pick your accent") {
                        VStack(alignment: .leading, spacing: 10) {
                            KitSettingRow(title: "Base") {
                                KitRadioGroup(options: [("dark", "Dark"), ("light", "Light")], selection: $hub.settings.look.customBase, label: "Base", horizontal: true)
                            }
                            KitSettingRow(title: "Accent", detail: "Accent is used for buttons, active states, and focus rings.") {
                                KitColorField(hex: $hub.settings.look.customAccent, label: "Accent colour")
                            }
                        }
                    }
                }
                if look.theme.hasPrefix("ctp-") {
                    KitDivider()
                    KitSettingRow(title: "Status colours", detail: "Priority dots, overdue, done and warnings") {
                        KitRadioGroup(options: [("catppuccin", "Catppuccin"), ("tailwind", "Classic (Tailwind)")],
                                      selection: Binding(get: { look.statusColors == "tailwind" ? "tailwind" : "catppuccin" }, set: { hub.settings.look.statusColors = $0 }), label: "Status colours", horizontal: true)
                    }
                }
                HStack(spacing: 12) {
                    Button("Save appearance") {
                        Task { if await hub.settings.saveAppearance() { try? await app.loadMe() } }
                    }
                    .buttonStyle(KitButtonStyle(.primary)).disabled(!hub.settings.isAppearanceDirty)
                    if hub.settings.isAppearanceDirty {
                        KitLinkButton(title: "Undo", size: 12, tone: .muted) { hub.settings.revertAppearance(); app.theme = Theme.resolve(app.me?.appearance) }
                    }
                }
            }
        }
        .task { if !hub.settings.loaded { await hub.settings.load() } }
        .onChange(of: look) { preview() }
    }

    private func choose(_ id: String) { hub.settings.look.theme = id }
}
