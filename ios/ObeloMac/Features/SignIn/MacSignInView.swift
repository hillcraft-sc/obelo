import AppKit
import AuthenticationServices
import SwiftUI

/// Sign-in (web: auth/login.ejs and auth/code.ejs). Username and password, single sign-on through the
/// in-app sheet, and the setup-code form, which swaps in place of the sign-in form. Every Obelo is
/// self-hosted, so the screen also shows which server it will use, and lets you change it.
struct MacSignInView: View {
    @Environment(AppState.self) private var app
    @Environment(\.theme) private var theme

    private enum Mode { case signIn, setupCode }
    @State private var mode: Mode = .signIn

    @State private var server = APIClient.shared.storedServer
    @State private var serverBeforeEdit = ""
    @State private var editingServer = false
    @State private var username = ""
    @State private var password = ""
    @State private var passwordBusy = false
    @State private var ssoBusy = false

    @State private var codeUsername = ""
    @State private var code = ""
    @State private var newPassword = ""
    @State private var again = ""
    @State private var codeError: String?
    @State private var codeBusy = false

    @State private var focusUsername = false
    @State private var focusPassword = false
    @State private var focusServer = false
    @State private var focusCodeUsername = false
    @State private var focusCode = false
    @State private var focusNewPassword = false
    @State private var focusAgain = false

    private var busy: Bool { passwordBusy || ssoBusy || app.signingIn }
    private var canSignIn: Bool { !username.isEmpty && !password.isEmpty && !busy }
    private var canSaveCode: Bool { !codeUsername.isEmpty && !code.isEmpty && !newPassword.isEmpty && !again.isEmpty && !codeBusy }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                header
                switch mode {
                case .signIn: signInForm
                case .setupCode: setupCodeForm
                }
            }
            .frame(maxWidth: 384)
            .padding(.horizontal, 16).padding(.top, 72).padding(.bottom, 32)
            .frame(maxWidth: .infinity)
        }
        .scrollEdgeEffectHidden(true, for: .top)
        .background(theme.page)
        .task {
            #if DEBUG
            applyPreviewState()
            #endif
            try? await Task.sleep(for: .milliseconds(150))
            if mode == .signIn, !editingServer { focusUsername = true }
        }
    }

    // ── Header ──────────────────────────────────────────────────────────────

    private var header: some View {
        VStack(spacing: 4) {
            Image("Logo").resizable().frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.bottom, 12)
                .accessibilityHidden(true)
            switch mode {
            case .signIn:
                Text("Obelo").font(.system(size: 24, weight: .bold)).foregroundStyle(theme.textPrimary)
                Text("Your self-hosted personal productivity hub").font(.system(size: 14)).foregroundStyle(theme.text400)
                Text("Notes · Tasks · Reminders · Routines · Calendar · Lists · AI")
                    .font(.system(size: 12)).foregroundStyle(theme.textMuted)
                    .multilineTextAlignment(.center).padding(.top, 10)
            case .setupCode:
                Text("Use a setup code").font(.system(size: 24, weight: .bold)).foregroundStyle(theme.textPrimary)
                Text("Your admin gave you a username and a setup code. Enter them, then choose your own password.")
                    .font(.system(size: 14)).foregroundStyle(theme.text400).multilineTextAlignment(.center)
            }
        }
        .padding(.bottom, 24)
    }

    // ── Sign in ─────────────────────────────────────────────────────────────

    private var signInForm: some View {
        VStack(spacing: 0) {
            Text("A private, self-hosted app for managing your notes, tasks, routines, calendar, and analytics — all in one place.")
                .font(.system(size: 12)).foregroundStyle(theme.textMuted)
                .multilineTextAlignment(.center).lineSpacing(3)
                .padding(.horizontal, 16).padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(theme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(theme.border1))
                .padding(.bottom, 24)

            if let error = app.signInError {
                KitBanner(kind: .error, text: error).padding(.bottom, 16)
            }

            VStack(spacing: 10) {
                KitTextField(placeholder: "Username or email", text: $username,
                             onSubmit: { focusPassword = true }, focusRequest: $focusUsername, contentType: .username)
                KitSecureField(placeholder: "Password", text: $password,
                               onSubmit: { submitPassword() }, focusRequest: $focusPassword)
                Button("Sign in") { submitPassword() }
                    .buttonStyle(KitButtonStyle(.primary, busy: passwordBusy, fullWidth: true))
                    .disabled(!canSignIn)
            }
            .padding(.bottom, 12)

            KitLinkButton(title: "Have a setup code?") { show(.setupCode) }
                .padding(.bottom, 16)

            Text("or").font(.system(size: 12)).foregroundStyle(theme.textMuted).padding(.bottom, 16)

            Button { Task { await signInWithSSO() } } label: {
                HStack(spacing: 10) {
                    if !ssoBusy { Image(systemName: "key.fill").foregroundStyle(theme.accentText) }
                    Text("Continue with single sign-on")
                }
            }
            .buttonStyle(KitButtonStyle(.secondary, busy: ssoBusy, fullWidth: true))
            .disabled(busy)

            serverLine.padding(.top, 28)

            #if DEBUG
            Button("Developer sign-in (local server)") { Task { await app.devSignIn(server: server) } }
                .buttonStyle(KitButtonStyle(.ghost, small: true))
                .padding(.top, 16)
            #endif
        }
    }

    private func submitPassword() {
        guard canSignIn else { return }
        passwordBusy = true
        Task {
            await app.passwordSignIn(server: server, username: username, password: password)
            passwordBusy = false
        }
    }

    private func signInWithSSO() async {
        ssoBusy = true
        await app.signIn(server: server, anchor: NSApp.keyWindow ?? NSApp.windows.first ?? NSWindow())
        ssoBusy = false
    }

    // ── Server ──────────────────────────────────────────────────────────────

    @ViewBuilder private var serverLine: some View {
        if editingServer {
            KitTextField(placeholder: "https://obelo.example.com", text: $server,
                         onSubmit: { editingServer = false }, focusRequest: $focusServer,
                         onCancel: { server = serverBeforeEdit; editingServer = false })
        } else {
            HStack(spacing: 6) {
                Image(systemName: "server.rack").font(.system(size: 11))
                Text(URL(string: server)?.host() ?? server).font(.system(size: 12))
                KitLinkButton(title: "Change", size: 12) {
                    serverBeforeEdit = server
                    editingServer = true
                    focusServer = true
                }
                .help("Change the server address")
            }
            .foregroundStyle(theme.textMuted)
            .accessibilityElement(children: .contain)
        }
    }

    // ── Setup code ──────────────────────────────────────────────────────────

    private var setupCodeForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let codeError { KitBanner(kind: .error, text: codeError) }
            KitFieldLabel(text: "Username") {
                KitTextField(placeholder: "Your username", text: $codeUsername,
                             onSubmit: { focusCode = true }, focusRequest: $focusCodeUsername, contentType: .username)
            }
            KitFieldLabel(text: "Setup code") {
                KitTextField(placeholder: "XXXX-XXXX", text: $code,
                             onSubmit: { focusNewPassword = true }, focusRequest: $focusCode)
            }
            KitFieldLabel(text: "New password (at least 10 characters)") {
                KitSecureField(placeholder: "Password", text: $newPassword,
                               onSubmit: { focusAgain = true }, focusRequest: $focusNewPassword, contentType: .newPassword)
            }
            KitFieldLabel(text: "New password again") {
                KitSecureField(placeholder: "Password again", text: $again,
                               onSubmit: { submitCode() }, focusRequest: $focusAgain, contentType: .newPassword)
            }
            Button("Save password") { submitCode() }
                .buttonStyle(KitButtonStyle(.primary, busy: codeBusy, fullWidth: true))
                .disabled(!canSaveCode)
            KitLinkButton(title: "Back to sign in", size: 14) { show(.signIn) }
                .frame(maxWidth: .infinity)
                .padding(.top, 2)
        }
        .task { try? await Task.sleep(for: .milliseconds(150)); focusCodeUsername = true }
    }

    private func submitCode() {
        guard canSaveCode else { return }
        codeError = nil
        guard newPassword == again else { codeError = "The two passwords don't match"; return }
        codeBusy = true
        Task {
            codeError = await app.setPasswordWithCode(server: server, username: codeUsername, code: code, password: newPassword)
            codeBusy = false
        }
    }

    private func show(_ next: Mode) {
        app.signInError = nil
        codeError = nil
        mode = next
        if next == .signIn { Task { try? await Task.sleep(for: .milliseconds(100)); focusUsername = true } }
    }

    #if DEBUG
    /// Testing: `-signInState filled | error | address | code` starts the screen in that state
    private func applyPreviewState() {
        switch UserDefaults.standard.string(forKey: "signInState") {
        case "filled": username = "sample"; password = "not-a-real-password"
        case "error": username = "sample"; app.signInError = "Invalid username or password."
        case "address": serverBeforeEdit = server; editingServer = true
        case "code": mode = .setupCode; codeError = "That setup code isn't valid or has expired."
        default: break
        }
    }
    #endif
}
