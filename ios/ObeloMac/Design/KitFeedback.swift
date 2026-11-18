import SwiftUI

// Feedback: the confirm dialog, the toast, and the tooltip helper.

extension View {
    /// A tooltip that VoiceOver also reads, for anything that isn't a KitIconButton
    func kitHelp(_ text: String) -> some View {
        help(text).accessibilityLabel(text)
    }

    /// The same dialog for "this thing is waiting for a yes". The thing is handed to the action as it was when the
    /// dialog opened: SwiftUI clears the binding before the button's action runs, so an action that read it back
    /// from the screen's state would find nothing and quietly do nothing.
    func kitConfirm<Item>(_ title: String, item: Binding<Item?>, confirmLabel: String,
                          destructive: Bool = false, message: String? = nil, action: @escaping (Item) -> Void) -> some View {
        confirmationDialog(title, isPresented: Binding(get: { item.wrappedValue != nil }, set: { if !$0 { item.wrappedValue = nil } }),
                           titleVisibility: .visible, presenting: item.wrappedValue) { value in
            Button(confirmLabel, role: destructive ? .destructive : nil) { action(value) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            if let message { Text(message) }
        }
    }

    /// The system confirmation dialog, worded the way the web's confirm() is ("Delete this task?")
    func kitConfirm(_ title: String, isPresented: Binding<Bool>, confirmLabel: String,
                    destructive: Bool = false, message: String? = nil, action: @escaping () -> Void) -> some View {
        confirmationDialog(title, isPresented: isPresented, titleVisibility: .visible) {
            Button(confirmLabel, role: destructive ? .destructive : nil, action: action)
            Button("Cancel", role: .cancel) {}
        } message: {
            if let message { Text(message) }
        }
    }
}

/// Shows one short message at the bottom of the window, then removes it
@Observable
final class KitToastCenter {
    private(set) var message: String?
    private(set) var isError = false
    private var generation = 0

    func show(_ message: String, isError: Bool = false) {
        generation += 1
        let mine = generation
        self.message = message
        self.isError = isError
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(isError ? 5 : 3))
            guard let self, self.generation == mine else { return }
            self.message = nil
        }
    }

    func dismiss() { message = nil }
}

struct KitToastOverlay: View {
    @Environment(\.theme) private var theme
    let center: KitToastCenter

    var body: some View {
        VStack {
            Spacer()
            if let message = center.message {
                HStack(spacing: 8) {
                    Image(systemName: center.isError ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(center.isError ? theme.red400 : theme.green400)
                    Text(message).font(.system(size: 14)).foregroundStyle(theme.text100)
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(theme.elevated, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(theme.border2))
                .shadow(color: .black.opacity(0.3), radius: 10, y: 4)
                .padding(.bottom, 20)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .animation(.easeOut(duration: 0.2), value: center.message)
        .allowsHitTesting(false)
    }
}
