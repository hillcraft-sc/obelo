import AppKit
import SwiftUI

/// Settings ▸ Notifications: where alerts are sent (Pushover, ntfy, email) and which kinds you get
struct NotificationsPane: View {
    @Environment(\.theme) private var theme
    @Environment(AppState.self) private var app
    @Bindable var hub: SettingsHub
    @State private var confirmNewTopic = false
    private var demo: Bool { app.me?.demo == true }

    private var store: NotificationSettingsStore { hub.notifications }

    var body: some View {
        SettingsPage(notice: $hub.notifications.notice) {
            if demo {
                KitBanner(kind: .warn, text: "Calendar accounts and notification channels aren't available on the demo. Run your own Obelo server to connect them.")
            } else if let s = store.settings {
                channels(s)
                types
                HStack(spacing: 10) {
                    Button("Save notification settings") { Task { await hub.notifications.save() } }
                        .buttonStyle(KitButtonStyle(.primary)).disabled(!store.isDirty)
                    if s.ntfyAvailable && s.ntfyEnabled {
                        Button("Send test ntfy notification") { Task { await hub.notifications.test("ntfy") } }.buttonStyle(KitButtonStyle(.secondary))
                        Button("New ntfy topic") { confirmNewTopic = true }.buttonStyle(KitButtonStyle(.secondary))
                    }
                    if s.emailAvailable { Button("Send test email") { Task { await hub.notifications.test("email") } }.buttonStyle(KitButtonStyle(.secondary)) }
                }
            } else {
                KitEmptyState(message: "Loading…")
            }
        }
        .task { await hub.notifications.load() }
        .kitConfirm("Create a new ntfy topic? You'll need to subscribe to the new one in the ntfy app; the old topic stops receiving notifications.",
                    isPresented: $confirmNewTopic, confirmLabel: "New topic") { Task { await hub.notifications.newTopic() } }
    }

    // ── Delivery channels ───────────────────────────────────────────────────

    private func channels(_ s: NotificationSettings) -> some View {
        SettingsCard(title: "Delivery channels") {
            VStack(alignment: .leading, spacing: 10) {
                channelHeader("Pushover", "Native push via the Pushover app")
                KitTextField(placeholder: "Paste your user key from pushover.net", text: Binding(get: { s.pushoverKey }, set: { hub.notifications.draft?.pushoverKey = $0 }))
                KitCheckbox(title: "Enable Pushover", isOn: Binding(get: { s.pushoverEnabled }, set: { hub.notifications.draft?.pushoverEnabled = $0 }))
            }
            KitDivider()
            VStack(alignment: .leading, spacing: 10) {
                channelHeader("ntfy", "Free push notifications via the ntfy app")
                if !s.ntfyAvailable {
                    Text(NotificationSettingsStore.ntfyNotConfigured).font(.system(size: 12)).foregroundStyle(theme.textMuted)
                } else {
                    KitCheckbox(title: "Enable ntfy", isOn: Binding(get: { s.ntfyEnabled }, set: { hub.notifications.draft?.ntfyEnabled = $0 }))
                    if s.ntfyEnabled && !s.ntfyTopic.isEmpty {
                        Text("In the ntfy app (iOS / Android), tap +, turn on Use another server, and enter:").font(.system(size: 12)).foregroundStyle(theme.textMuted)
                        copyRow("Server", s.ntfyServer)
                        copyRow("Topic", s.ntfyTopic)
                        Text("Keep the topic private — anyone who knows it can read your notifications.").font(.system(size: 12)).foregroundStyle(theme.textMuted)
                    } else {
                        Text("Turn this on and save to get your personal topic and subscribe instructions.").font(.system(size: 12)).foregroundStyle(theme.textMuted)
                    }
                }
            }
            KitDivider()
            VStack(alignment: .leading, spacing: 10) {
                channelHeader("Email", "Sent via SMTP")
                KitFieldLabel(text: "Delivery email address") {
                    KitTextField(placeholder: s.accountEmail, text: Binding(get: { s.notifEmail }, set: { hub.notifications.draft?.notifEmail = $0 }))
                }
                if !s.accountEmail.isEmpty {
                    Text("Leave blank to use your profile email (\(s.accountEmail))").font(.system(size: 12)).foregroundStyle(theme.textMuted)
                } else {
                    Text("Add an email to your profile (Account tab) to use as the default").font(.system(size: 12)).foregroundStyle(theme.textMuted)
                }
            }
        }
    }

    private func channelHeader(_ name: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(name).font(.system(size: 14, weight: .medium)).foregroundStyle(theme.text200)
            Text(detail).font(.system(size: 12)).foregroundStyle(theme.textMuted)
        }
    }

    private func copyRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: 10) {
            Text(label).font(.system(size: 12)).foregroundStyle(theme.textMuted).frame(width: 46, alignment: .leading)
            Text(value).font(.system(size: 12, design: .monospaced)).foregroundStyle(theme.text200).textSelection(.enabled)
            Spacer(minLength: 0)
            KitIconButton(systemImage: "doc.on.doc", label: "Copy \(label.lowercased())") {
                NSPasteboard.general.clearContents(); NSPasteboard.general.setString(value, forType: .string)
                hub.notifications.notice = SettingsNotice(text: "Copied \(label.lowercased())", isError: false)
            }
        }
    }

    // ── Notification types ──────────────────────────────────────────────────

    private var types: some View {
        SettingsCard(title: "Notification types", detail: "Reminders and routine alerts fire automatically at their scheduled times, to every push channel you've enabled above.") {
            ForEach(Array(NotificationSettingsStore.types.enumerated()), id: \.element.key) { i, info in
                if i > 0 { KitDivider() }
                if let pref = store.settings?.types[info.key] {
                    VStack(alignment: .leading, spacing: 10) {
                        KitSettingRow(title: info.label, detail: info.detail) {
                            KitCheckbox(title: info.label, isOn: Binding(get: { pref.enabled }, set: { v in hub.notifications.setType(info.key) { $0.enabled = v } }), showsTitle: false)
                        }
                        if pref.enabled {
                            if info.timed {
                                KitSettingRow(title: "Send at") {
                                    KitTimeField(value: Binding(get: { Fmt.date(fromHHMM: pref.sendTime) },
                                                                set: { v in hub.notifications.setType(info.key) { $0.sendTime = Fmt.hhmm(from: v) } }), label: "Send at")
                                }
                            }
                            HStack(spacing: 16) {
                                KitCheckbox(title: "Pushover", isOn: Binding(get: { pref.channels.pushover }, set: { v in hub.notifications.setType(info.key) { $0.channels.pushover = v } }))
                                KitCheckbox(title: "Email", isOn: Binding(get: { pref.channels.email }, set: { v in hub.notifications.setType(info.key) { $0.channels.email = v } }))
                                KitCheckbox(title: "ntfy", isOn: Binding(get: { pref.channels.ntfy }, set: { v in hub.notifications.setType(info.key) { $0.channels.ntfy = v } }))
                            }
                        }
                    }
                }
            }
        }
    }
}
