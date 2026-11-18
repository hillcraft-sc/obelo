import SwiftUI

/// The sidebar (web: partials/sidebar.ejs): wordmark, search trigger, the modules in their groups,
/// then the signed-in user, Help and the version. Admin pages stay web-only (plan decision 5).
struct MacSidebar: View {
    @Environment(AppState.self) private var app
    @Environment(Navigator.self) private var nav
    @Environment(\.openSettings) private var openSettings
    @Environment(\.theme) private var theme

    private var enabled: [String] { app.me?.modules.map(\.key) ?? ["dashboard"] }

    var body: some View {
        VStack(spacing: 0) {
            // Clear of the traffic lights, the same on every screen (a screen with a toolbar has a taller title bar)
            Color.clear.frame(height: 40)
            Text("Obelo")
                .font(.system(size: 24, weight: .bold)).tracking(-0.4)
                .foregroundStyle(theme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20).padding(.vertical, 14)
                .overlay(alignment: .bottom) { KitDivider() }

            searchTrigger.padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 4)

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(SidebarGroups.groups(enabled: enabled)) { group in
                        if let title = group.title {
                            Text(title.uppercased())
                                .font(.system(size: 10, weight: .semibold)).tracking(0.6)
                                .foregroundStyle(theme.textMuted)
                                .padding(.horizontal, 12).padding(.top, 14).padding(.bottom, 4)
                                .accessibilityAddTraits(.isHeader)
                        }
                        ForEach(group.keys, id: \.self) { key in
                            MacSidebarItem(key: key, selected: nav.selected == key) { select(key) }
                        }
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
            }

            footer
        }
        .ignoresSafeArea(.container, edges: .top)
        .background(theme.surface.ignoresSafeArea())
        .overlay(alignment: .trailing) { Rectangle().fill(theme.border1).frame(width: 1).ignoresSafeArea() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Sidebar")
    }

    private var searchTrigger: some View {
        Button { nav.searchOpen = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 12))
                Text("Search").font(.system(size: 14))
                Spacer()
                Text("/").font(.system(size: 10, design: .monospaced))
                    .padding(.horizontal, 4)
                    .background(theme.h2, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(theme.border3))
            }
            .foregroundStyle(theme.textMuted)
            .kitFieldChrome(hPadding: 12, vPadding: 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Search (⌘K or /)")
        .accessibilityLabel("Search")
    }

    private var footer: some View {
        VStack(spacing: 0) {
            KitDivider()
            HStack(spacing: 12) {
                Button { openSettings() } label: {
                    HStack(spacing: 12) {
                        KitProfileImage(url: app.me?.avatarUrl, name: app.me?.user.displayName ?? initial, size: 32)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(app.me?.user.displayName ?? "")
                                .font(.system(size: 14, weight: .medium)).foregroundStyle(theme.text100).lineLimit(1)
                            Text("@\(app.me?.user.username ?? "")")
                                .font(.system(size: 12)).foregroundStyle(theme.textMuted).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Settings (⌘,)")
                .accessibilityLabel("Settings, signed in as \(app.me?.user.displayName ?? "")")

                KitIconButton(systemImage: "rectangle.portrait.and.arrow.right", label: "Sign out") {
                    Task { await app.signOut() }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 14)

            HStack(spacing: 16) {
                Button { nav.helpRequest += 1 } label: {
                    Label("Help", systemImage: "questionmark.circle").font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .help("Help (⌘?)")
                if let version = app.me?.version {
                    Text("v\(version)").font(.system(size: 10, design: .monospaced)).help("Server version")
                }
            }
            .foregroundStyle(theme.textMuted)
            .padding(.bottom, 12)
        }
    }

    private var initial: String {
        String((app.me?.user.displayName ?? "?").prefix(1)).uppercased()
    }

    private func select(_ key: String) { nav.selected = key }
}

private struct MacSidebarItem: View {
    @Environment(\.theme) private var theme
    @State private var hovering = false
    let key: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        let meta = ModuleMeta.of(key)
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: meta.icon).font(.system(size: 14)).frame(width: 18)
                Text(meta.label).font(.system(size: 14, weight: .medium))
                Spacer(minLength: 0)
            }
            .foregroundStyle(selected ? theme.onAccent : hovering ? theme.text100 : theme.text400)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(selected ? theme.accent : hovering ? theme.elevated : .clear,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(meta.label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
