import AppKit
import SwiftUI

/// Settings ▸ Account: profile, password, signed-in devices, note lock PIN, delete account
struct AccountPane: View {
    @Environment(AppState.self) private var app
    @Environment(\.theme) private var theme
    @Bindable var hub: SettingsHub

    @State private var endingDevice: DeviceSession?
    @State private var confirmEndOthers = false
    @State private var currentPin = ""
    @State private var newPin = ""
    @State private var confirmPin = ""
    @State private var showRemovePin = false
    @State private var removePinText = ""
    @State private var showDelete = false
    @State private var typedUsername = ""
    @State private var confirmDelete = false

    private var s: SettingsStore { hub.settings }

    var body: some View {
        SettingsPage(notice: $hub.settings.notice) {
            if s.loaded {
                profile
                if s.offersPassword && app.me?.demo != true { password }
                devices
                lockPin
                danger
            } else {
                KitEmptyState(message: "Loading…")
            }
        }
        .task {
            await hub.settings.load()
            await hub.notes.load()
        }
        .kitConfirm(endingDevice.map { "Sign out \($0.device)?" } ?? "", item: $endingDevice, confirmLabel: "Sign out", destructive: true) { device in
            Task { await hub.settings.endSession(device.key) }
        }
        .kitConfirm(SettingsStore.endOthersQuestion(s.otherSessions.count), isPresented: $confirmEndOthers, confirmLabel: "Sign out", destructive: true) {
            Task { await hub.settings.endOtherSessions() }
        }
        .kitConfirm("This will permanently delete your account and ALL your data. Are you absolutely sure?", isPresented: $confirmDelete,
                    confirmLabel: "Delete everything", destructive: true) {
            Task {
                if await hub.settings.deleteAccount(typed: typedUsername) {
                    APIClient.shared.clearCookies()
                    await app.signOut()
                }
            }
        }
    }

    // ── Profile ─────────────────────────────────────────────────────────────

    private static let zones: [String] = {
        let common = ["America/New_York", "America/Chicago", "America/Denver", "America/Los_Angeles", "America/Phoenix", "America/Anchorage",
                      "Pacific/Honolulu", "Europe/London", "Europe/Paris", "Europe/Berlin", "Asia/Tokyo", "Asia/Shanghai", "Asia/Kolkata", "Australia/Sydney"]
        return common + TimeZone.knownTimeZoneIdentifiers.filter { !common.contains($0) }.sorted()
    }()

    private var profile: some View {
        SettingsCard(title: "Profile", detail: "Click avatar to upload a photo") {
            HStack(spacing: 14) {
                KitProfileImage(url: s.data?.account.avatarUrl, name: s.account.displayName, size: 56)
                VStack(alignment: .leading, spacing: 6) {
                    KitFileButton(title: "Choose photo…", systemImage: "photo", types: [.image]) { urls in
                        guard let url = urls.first, let jpeg = KitProfileImage.jpeg(from: url, maxSide: 512) else {
                            hub.settings.notice = SettingsNotice(text: "Couldn't read that picture.", isError: true); return
                        }
                        Task { await hub.settings.uploadAvatar(jpeg); KitProfileImage.bustCache(); try? await app.loadMe() }
                    }
                    if s.data?.account.hasCustomAvatar == true {
                        KitLinkButton(title: "Remove custom avatar", size: 12, tone: .muted) { Task { await hub.settings.removeAvatar(); KitProfileImage.bustCache(); try? await app.loadMe() } }
                    } else if !s.account.email.isEmpty {
                        Text("Using Gravatar").font(.system(size: 12)).foregroundStyle(theme.textMuted)
                    }
                }
            }
            KitFieldLabel(text: "Display name") { KitTextField(placeholder: "Your name", text: $hub.settings.account.displayName, onSubmit: saveProfile) }
            KitFieldLabel(text: "Email address") {
                VStack(alignment: .leading, spacing: 4) {
                    KitTextField(placeholder: "you@example.com", text: $hub.settings.account.email, onSubmit: saveProfile)
                    Text("Used for Gravatar and notification delivery").font(.system(size: 12)).foregroundStyle(theme.textMuted)
                }
            }
            KitFieldLabel(text: "Time Format") {
                KitRadioGroup(options: [("12h", "12-hour (1:30 PM)"), ("24h", "24-hour (13:30)")], selection: $hub.settings.account.timeFormat, label: "Time format", horizontal: true)
            }
            KitFieldLabel(text: "Timezone") {
                KitSelect(options: (Self.zones.contains(s.account.timezone) ? Self.zones : [s.account.timezone] + Self.zones).map { ($0, $0.replacingOccurrences(of: "_", with: " ")) },
                          selection: $hub.settings.account.timezone, label: "Timezone")
            }
            Button("Save profile", action: saveProfile).buttonStyle(KitButtonStyle(.primary)).disabled(!s.isAccountDirty)
        }
    }

    private func saveProfile() {
        Task {
            if await hub.settings.saveAccount() {
                try? await app.loadMe()
                app.dataChanged()
            }
        }
    }

    // ── Password ────────────────────────────────────────────────────────────

    private var password: some View {
        SettingsCard(title: s.hasPassword ? "Password" : "Add a password",
                     detail: s.hasPassword ? "Changing it signs you out of your other devices."
                                           : "You sign in with SSO now. A password lets you sign in without it too.") {
            if s.hasPassword {
                KitFieldLabel(text: "Current password") { KitSecureField(placeholder: "", text: $hub.settings.password.current, contentType: .password) }
            }
            KitFieldLabel(text: "New password") { KitSecureField(placeholder: "", text: $hub.settings.password.new, contentType: .newPassword) }
            KitFieldLabel(text: "New password again") {
                KitSecureField(placeholder: "", text: $hub.settings.password.again, isError: s.passwordProblem != nil, onSubmit: savePassword, contentType: .newPassword)
            }
            if let problem = s.passwordProblem { Text(problem).font(.system(size: 12)).foregroundStyle(theme.red400) }
            Button(s.hasPassword ? "Change password" : "Save password", action: savePassword)
                .buttonStyle(KitButtonStyle(.primary)).disabled(!s.canSavePassword)
        }
    }

    private func savePassword() { if s.canSavePassword { Task { await hub.settings.savePassword() } } }

    // ── Devices ─────────────────────────────────────────────────────────────

    private func when(_ date: Date?) -> String {
        guard let date else { return "Unknown" }
        return SettingsFormat.when(date, hour12: app.hour12, timezone: s.account.timezone)
    }

    private var devices: some View {
        SettingsCard(title: "Signed-in devices", detail: "Where you're signed in to Obelo right now. Sign out anything you don't recognise.") {
            VStack(spacing: 0) {
                ForEach(s.sessions) { d in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(d.device).font(.system(size: 14)).foregroundStyle(theme.text100)
                                if d.current { Text("(this device)").font(.system(size: 12)).foregroundStyle(theme.green400) }
                            }
                            Text("Signed in \(when(d.signedInAt)) · Last active \(when(d.lastSeenAt))" + (d.ip.map { " · \($0)" } ?? ""))
                                .font(.system(size: 12)).foregroundStyle(theme.textMuted)
                        }
                        Spacer()
                        if !d.current { Button("Sign out") { endingDevice = d }.buttonStyle(KitButtonStyle(.secondary, small: true)) }
                    }
                    .padding(.vertical, 10)
                    .overlay(alignment: .bottom) { if d.id != s.sessions.last?.id { KitDivider() } }
                    .accessibilityElement(children: .combine)
                }
            }
            if !s.otherSessions.isEmpty {
                Button("Sign out all other devices") { confirmEndOthers = true }.buttonStyle(KitButtonStyle(.secondary))
            }
        }
    }

    // ── Note Lock PIN ───────────────────────────────────────────────────────

    private func digitsOnly(_ text: Binding<String>) -> Binding<String> {
        Binding(get: { text.wrappedValue }, set: { text.wrappedValue = String($0.filter(\.isNumber).prefix(6)) })
    }

    private var lockPin: some View {
        SettingsCard(title: "Note Lock PIN", detail: "4–6 digit PIN required to unlock encrypted notes. Works with any login method including SSO.") {
            if hub.notes.hasPin {
                Label("PIN set", systemImage: "checkmark").font(.system(size: 12)).foregroundStyle(theme.green400)
            } else {
                Text("Not set — notes cannot be locked until you create a PIN").font(.system(size: 12)).foregroundStyle(theme.textMuted)
            }
            if hub.notes.hasPin {
                KitFieldLabel(text: "Current PIN") { KitSecureField(placeholder: "", text: digitsOnly($currentPin), contentType: .oneTimeCode).frame(width: 140) }
            }
            KitFieldLabel(text: (hub.notes.hasPin ? "New PIN" : "PIN") + " (4–6 digits)") { KitSecureField(placeholder: "", text: digitsOnly($newPin), contentType: .oneTimeCode).frame(width: 140) }
            KitFieldLabel(text: "Confirm PIN") { KitSecureField(placeholder: "", text: digitsOnly($confirmPin), onSubmit: setPin, contentType: .oneTimeCode).frame(width: 140) }
            HStack(spacing: 12) {
                Button(hub.notes.hasPin ? "Change PIN" : "Set PIN", action: setPin).buttonStyle(KitButtonStyle(.primary))
                    .disabled(newPin.isEmpty || confirmPin.isEmpty)
                if hub.notes.hasPin { KitLinkButton(title: showRemovePin ? "Cancel" : "Remove PIN", size: 12, tone: .muted) { showRemovePin.toggle(); removePinText = "" } }
            }
            if showRemovePin {
                HStack(spacing: 8) {
                    KitSecureField(placeholder: "Current PIN", text: digitsOnly($removePinText), contentType: .oneTimeCode).frame(width: 140)
                    Button("Remove") {
                        Task { if await hub.notes.removePin(current: removePinText) { removePinText = ""; showRemovePin = false; try? await app.loadMe() } }
                    }
                    .buttonStyle(KitButtonStyle(.danger)).disabled(removePinText.isEmpty)
                }
            }
        }
        .onChange(of: hub.notes.notice) { _, n in if let n { hub.settings.notice = n } }
    }

    private func setPin() {
        Task {
            if await hub.notes.setPin(current: currentPin, new: newPin, confirm: confirmPin) {
                currentPin = ""; newPin = ""; confirmPin = ""
                try? await app.loadMe()
            }
        }
    }

    // ── Danger zone ─────────────────────────────────────────────────────────

    private var danger: some View {
        SettingsCard(title: "Danger Zone", detail: "Permanently delete your account and all your data. This cannot be undone.", danger: true) {
            KitLinkButton(title: showDelete ? "Hide" : "Delete my account", size: 12) { showDelete.toggle(); typedUsername = "" }
            if showDelete {
                Text("Type your username \(s.data?.account.username ?? "") to confirm.").font(.system(size: 12)).foregroundStyle(theme.textMuted)
                KitTextField(placeholder: s.data?.account.username ?? "", text: $typedUsername)
                Button("Permanently delete account") { confirmDelete = true }
                    .buttonStyle(KitButtonStyle(.danger)).disabled(!s.canDeleteAccount(typed: typedUsername))
            }
        }
    }
}
