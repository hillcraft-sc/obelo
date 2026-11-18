import SwiftUI
import AuthenticationServices
#if os(iOS)
import UIKit
#endif

// The web's sign-in page (views/auth/login.ejs) plus a server address field, since every
// Obelo is self-hosted.

struct LoginView: View {
    @Environment(AppState.self) private var app
    @Environment(\.theme) private var theme
    @State private var server = APIClient.shared.storedServer
    @State private var editingServer = false
    @State private var username = ""
    @State private var password = ""
    @State private var showingSetupCode = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Spacer(minLength: 80)
                VStack(spacing: 4) {
                    Image("Logo").resizable().frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .padding(.bottom, 12)
                    Text("Obelo").font(.system(size: 24, weight: .bold)).foregroundStyle(theme.textPrimary)
                    Text("Your self-hosted personal productivity hub")
                        .font(.system(size: 14)).foregroundStyle(theme.text400)
                    Text("Notes · Tasks · Reminders · Routines · Calendar · Lists · AI")
                        .font(.system(size: 12)).foregroundStyle(theme.textMuted)
                        .multilineTextAlignment(.center).padding(.top, 10)
                }
                .padding(.bottom, 24)

                Text("A private, self-hosted app for managing your notes, tasks, routines, calendar, and analytics — all in one place.")
                    .font(.system(size: 12)).foregroundStyle(theme.textMuted)
                    .multilineTextAlignment(.center).lineSpacing(3)
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .background(theme.surface, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.border1, lineWidth: 1))
                    .padding(.bottom, 24)

                if let error = app.signInError {
                    Banner(kind: .error, text: error).padding(.bottom, 16)
                }

                VStack(spacing: 10) {
                    ThemedField(placeholder: "Username or email", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.username)
                    SecureField("", text: $password, prompt: Text("Password").foregroundStyle(theme.placeholder))
                        .textContentType(.password)
                        .font(.system(size: 15)).foregroundStyle(theme.text100)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(theme.isDark ? theme.elevated : theme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(theme.border2, lineWidth: 1))
                        .onSubmit { submitPassword() }
                    PrimaryButton(title: "Sign in", fullWidth: true, busy: app.signingIn) { submitPassword() }
                        .disabled(username.isEmpty || password.isEmpty)
                        .opacity(username.isEmpty || password.isEmpty ? 0.5 : 1)
                }
                .padding(.bottom, 4)

                Button("Have a setup code?") { showingSetupCode = true }
                    .font(.system(size: 13)).foregroundStyle(theme.accentText)
                    .padding(.bottom, 16)

                Text("or").font(.system(size: 12)).foregroundStyle(theme.textMuted).padding(.bottom, 16)

                Button {
                    Task { await app.signIn(server: server, anchor: Self.anchor) }
                } label: {
                    HStack(spacing: 12) {
                        if app.signingIn {
                            ProgressView().tint(theme.textPrimary).controlSize(.small)
                        } else {
                            Image(systemName: "key.fill").font(.system(size: 18)).foregroundStyle(theme.accentText)
                        }
                        Text("Continue with single sign-on").font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(theme.textPrimary)
                    .frame(maxWidth: .infinity).padding(.vertical, 11)
                    .background(theme.elevated, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.border2, lineWidth: 1))
                }
                .buttonStyle(PressableStyle())
                .disabled(app.signingIn)

                serverSection.padding(.top, 28)

                #if DEBUG
                Button("Developer sign-in (local server)") {
                    Task { await app.devSignIn(server: server) }
                }
                .font(.system(size: 12)).foregroundStyle(theme.textMuted)
                .padding(.top, 20)
                #endif
            }
            .frame(maxWidth: 384)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
        }
        .background(theme.page)
        .sheet(isPresented: $showingSetupCode) { SetupCodeView(server: server) }
        #if DEBUG
        // Testing: `-autoSSO YES` starts the SSO sign-in on launch (to test the sign-in sheet's round trip)
        .task {
            if UserDefaults.standard.bool(forKey: "autoSSO") {
                try? await Task.sleep(for: .seconds(1))
                await app.signIn(server: server, anchor: Self.anchor)
            }
        }
        #endif
    }

    private func submitPassword() {
        guard !username.isEmpty, !password.isEmpty else { return }
        Task { await app.passwordSignIn(server: server, username: username, password: password) }
    }

    @ViewBuilder private var serverSection: some View {
        VStack(spacing: 8) {
            if editingServer {
                ThemedField(placeholder: "https://obelo.example.com", text: $server) { editingServer = false }
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
            } else {
                Button { editingServer = true } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "server.rack").font(.system(size: 11))
                        Text(URL(string: server)?.host() ?? server).font(.system(size: 12))
                        Text("Change").font(.system(size: 12, weight: .medium)).foregroundStyle(theme.accentText)
                    }
                    .foregroundStyle(theme.textMuted)
                }
                .buttonStyle(.plain)
            }
        }
    }

    static var anchor: ASPresentationAnchor {
        #if os(iOS)
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let key = scenes.flatMap(\.windows).first(where: \.isKeyWindow) { return key }
        return UIWindow(windowScene: scenes[0])
        #else
        return NSApp.keyWindow ?? NSApp.windows.first ?? NSWindow()
        #endif
    }
}
