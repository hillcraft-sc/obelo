import SwiftUI

/// Small async action runner that reports errors through a shared toast
@Observable
final class Toast {
    var message: String?
    var isError = false

    func show(_ text: String, error: Bool = false) {
        isError = error
        withAnimation { message = text }
        let current = text
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            if message == current { withAnimation { message = nil } }
        }
    }

    func run(_ work: @escaping () async throws -> Void) {
        Task {
            do { try await work() } catch { show(error.localizedDescription, error: true) }
        }
    }
}

struct ToastOverlay: View {
    @Environment(\.theme) private var theme
    let toast: Toast
    var body: some View {
        if let message = toast.message {
            Text(message)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(toast.isError ? Color(hex: "#fca5a5") : theme.text100)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(toast.isError ? Color(hex: "#450a0a") : theme.elevated, in: Capsule())
                .overlay(Capsule().stroke(toast.isError ? Color(hex: "#991b1b") : theme.border2, lineWidth: 1))
                .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
                .padding(.bottom, 90)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}
