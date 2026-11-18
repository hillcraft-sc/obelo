import SwiftUI

// Choosing a password with the setup code an admin gave you: the in-app version of the web's
// one-time link (views/auth/password.ejs). On success the app signs in with the new password.

struct SetupCodeView: View {
    @Environment(AppState.self) private var app
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    let server: String
    @State private var username = ""
    @State private var code = ""
    @State private var password = ""
    @State private var again = ""
    @State private var error: String?
    @State private var busy = false

    private var ready: Bool { !username.isEmpty && !code.isEmpty && !password.isEmpty && !again.isEmpty }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Your admin gave you a username and a setup code. Enter them, then choose your own password.")
                        .font(.system(size: 13)).foregroundStyle(theme.textMuted)
                    if let error { Banner(kind: .error, text: error) }
                    FormSection(label: "Username") {
                        ThemedField(placeholder: "Your username", text: $username)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .textContentType(.username)
                    }
                    FormSection(label: "Setup code") {
                        ThemedField(placeholder: "XXXX-XXXX", text: $code)
                            .textInputAutocapitalization(.characters).autocorrectionDisabled()
                    }
                    FormSection(label: "New password (at least 10 characters)") { passwordField("Password", $password) }
                    FormSection(label: "New password again") { passwordField("Password again", $again) }
                    PrimaryButton(title: "Save password and sign in", fullWidth: true, busy: busy) { submit() }
                        .disabled(!ready)
                        .opacity(ready ? 1 : 0.5)
                }
                .padding(16)
                .frame(maxWidth: 420)
                .frame(maxWidth: .infinity)
            }
            .background(theme.page)
            .themedNavBar(theme, title: "Setup code")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .presentationBackground(theme.page)
    }

    private func passwordField(_ placeholder: String, _ text: Binding<String>) -> some View {
        SecureField("", text: text, prompt: Text(placeholder).foregroundStyle(theme.placeholder))
            .textContentType(.newPassword)
            .font(.system(size: 15)).foregroundStyle(theme.text100)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(theme.isDark ? theme.elevated : theme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(theme.border2, lineWidth: 1))
    }

    private func submit() {
        error = nil
        guard password == again else { error = "The two passwords don't match"; return }
        busy = true
        Task {
            defer { busy = false }
            error = await app.setPasswordWithCode(server: server, username: username, code: code, password: password)
        }
    }
}
