import AppKit
import SwiftUI

// Form controls. Each wraps the macOS control (text field, text editor, pop-up menu, date picker,
// checkbox, radio group) in Obelo's colours (plan decision 9), so editing, keyboard, VoiceOver and
// focus come from the system.

/// The box around a field: elevated fill, hairline border, accent ring while focused, red when in error
struct KitFieldChrome: ViewModifier {
    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var isEnabled
    var focused = false
    var error = false
    var hPadding: CGFloat = 12
    var vPadding: CGFloat = 7

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        content
            .padding(.horizontal, hPadding).padding(.vertical, vPadding)
            .background(theme.elevated, in: shape)
            .overlay(shape.strokeBorder(error ? theme.red500 : focused ? theme.accentHover : theme.border2,
                                        lineWidth: focused || error ? 1.5 : 1))
            .overlay(shape.inset(by: -2).strokeBorder((error ? theme.red500 : theme.accentHover).opacity(focused ? 0.35 : 0), lineWidth: 2))
            .opacity(isEnabled ? 1 : 0.5)
    }
}

extension View {
    func kitFieldChrome(focused: Bool = false, error: Bool = false, hPadding: CGFloat = 12, vPadding: CGFloat = 7) -> some View {
        modifier(KitFieldChrome(focused: focused, error: error, hPadding: hPadding, vPadding: vPadding))
    }
}

/// A one-line text field. Return runs `onSubmit`.
struct KitTextField: View {
    @Environment(\.theme) private var theme
    @FocusState private var focused: Bool
    let placeholder: String
    @Binding var text: String
    var isError = false
    var onSubmit: (() -> Void)?
    /// Set to true from outside to move the cursor here (⌘F, a new task); the field sets it back to false
    var focusRequest: Binding<Bool>?
    /// Tells the system password manager what the field is (.username)
    var contentType: NSTextContentType?
    /// Escape
    var onCancel: (() -> Void)?

    var body: some View {
        TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(theme.placeholder))
            .textFieldStyle(.plain)
            .font(.system(size: 14))
            .foregroundStyle(theme.text100)
            .textContentType(contentType)
            .focused($focused)
            .onSubmit { onSubmit?() }
            .onExitCommand { onCancel?() }
            .onChange(of: focusRequest?.wrappedValue ?? false) { _, wanted in
                if wanted { focused = true; focusRequest?.wrappedValue = false }
            }
            .onAppear {
                if focusRequest?.wrappedValue == true { focused = true; focusRequest?.wrappedValue = false }
            }
            .kitFieldChrome(focused: focused, error: isError)
            .accessibilityLabel(placeholder)
    }
}

/// A password field: the system secure field in the same box as the text field. Return runs `onSubmit`.
struct KitSecureField: View {
    @Environment(\.theme) private var theme
    @FocusState private var focused: Bool
    let placeholder: String
    @Binding var text: String
    var isError = false
    var onSubmit: (() -> Void)?
    var focusRequest: Binding<Bool>?
    /// .password to sign in, .newPassword when choosing one
    var contentType: NSTextContentType = .password

    var body: some View {
        SecureField("", text: $text, prompt: Text(placeholder).foregroundStyle(theme.placeholder))
            .textFieldStyle(.plain)
            .font(.system(size: 14))
            .foregroundStyle(theme.text100)
            .textContentType(contentType)
            .focused($focused)
            .onSubmit { onSubmit?() }
            .onChange(of: focusRequest?.wrappedValue ?? false) { _, wanted in
                if wanted { focused = true; focusRequest?.wrappedValue = false }
            }
            .kitFieldChrome(focused: focused, error: isError)
            .accessibilityLabel(placeholder)
    }
}

/// The search field: a magnifier, a clear button once something is typed
struct KitSearchField: View {
    @Environment(\.theme) private var theme
    @FocusState private var focused: Bool
    let placeholder: String
    @Binding var text: String
    var onSubmit: (() -> Void)?
    var focusRequest: Binding<Bool>?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(theme.textMuted)
            TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(theme.placeholder))
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundStyle(theme.text100)
                .focused($focused)
                .onSubmit { onSubmit?() }
                .onChange(of: focusRequest?.wrappedValue ?? false) { _, wanted in
                    if wanted { focused = true; focusRequest?.wrappedValue = false }
                }
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 12)).foregroundStyle(theme.textMuted)
                }
                .buttonStyle(.plain)
                .help("Clear search")
                .accessibilityLabel("Clear search")
            }
        }
        .kitFieldChrome(focused: focused)
        .accessibilityElement(children: .contain)
    }
}

/// A multi-line text field
struct KitTextArea: View {
    @Environment(\.theme) private var theme
    @FocusState private var focused: Bool
    let placeholder: String
    @Binding var text: String
    var minHeight: CGFloat = 96
    var onFocusChange: ((Bool) -> Void)?
    var focusRequest: Binding<Bool>?

    var body: some View {
        TextEditor(text: $text)
            .font(.system(size: 14))
            .foregroundStyle(theme.text100)
            .scrollContentBackground(.hidden)
            .focused($focused)
            .onChange(of: focused) { _, now in onFocusChange?(now) }
            .onChange(of: focusRequest?.wrappedValue ?? false) { _, wanted in
                if wanted { focused = true; focusRequest?.wrappedValue = false }
            }
            .onAppear {
                if focusRequest?.wrappedValue == true { focused = true; focusRequest?.wrappedValue = false }
            }
            .frame(minHeight: minHeight)
            .overlay(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder).font(.system(size: 14)).foregroundStyle(theme.placeholder)
                        .padding(.leading, 5).allowsHitTesting(false)
                }
            }
            .kitFieldChrome(focused: focused, hPadding: 8, vPadding: 6)
            .accessibilityLabel(placeholder)
    }
}

/// A whole-number field with the system stepper (custom repeat: "every N days")
struct KitNumberField: View {
    @Environment(\.theme) private var theme
    @FocusState private var focused: Bool
    @Binding var value: Int
    var range: ClosedRange<Int> = 1...999
    var label: String

    var body: some View {
        HStack(spacing: 6) {
            TextField("", value: $value, format: .number)
                .textFieldStyle(.plain)
                .font(.system(size: 14)).monospacedDigit()
                .foregroundStyle(theme.text100)
                .multilineTextAlignment(.trailing)
                .focused($focused)
                .frame(width: 44)
                .kitFieldChrome(focused: focused)
                .onChange(of: value) { _, new in
                    let clamped = min(max(new, range.lowerBound), range.upperBound)
                    if clamped != new { value = clamped }
                }
            Stepper("", value: $value, in: range).labelsHidden()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }
}

/// A pop-up menu (the system menu, in Obelo's colours). `compact` is the borderless one used inside rows.
struct KitSelect<Value: Hashable>: View {
    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false
    let options: [(value: Value, label: String)]
    @Binding var selection: Value
    var label: String
    var compact = false
    /// Colour for the compact form's text (the web colours a task's status)
    var tint: Color?

    private var selectedLabel: String { options.first { $0.value == selection }?.label ?? "" }

    var body: some View {
        Menu {
            ForEach(options.indices, id: \.self) { i in
                Button {
                    selection = options[i].value
                } label: {
                    if options[i].value == selection {
                        Label(options[i].label, systemImage: "checkmark")
                    } else {
                        Text(options[i].label)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(selectedLabel)
                    .font(.system(size: compact ? 12 : 14, weight: compact ? .medium : .regular))
                    .foregroundStyle(tint ?? theme.text100)
                    .lineLimit(1)
                if !compact { Spacer(minLength: 4) }
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: compact ? 8 : 10, weight: .semibold))
                    .foregroundStyle(theme.textMuted)
            }
            .modifier(SelectBox(compact: compact, hovering: hovering))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize(horizontal: compact, vertical: true)
        .opacity(isEnabled ? 1 : 0.5)
        .onHover { hovering = $0 }
        .help(label)
        .accessibilityLabel(label)
        .accessibilityValue(selectedLabel)
    }
}

private struct SelectBox: ViewModifier {
    @Environment(\.theme) private var theme
    let compact: Bool
    let hovering: Bool

    func body(content: Content) -> some View {
        if compact {
            content
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(hovering ? theme.elevated : .clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        } else {
            content.kitFieldChrome(focused: hovering)
        }
    }
}

/// A date or a time that can also be empty (due date, due time). Empty shows a "Set" button.
struct KitOptionalDateField: View {
    @Environment(\.theme) private var theme
    let components: DatePicker<Text>.Components
    @Binding var value: Date?
    var label: String
    var emptyLabel: String

    var body: some View {
        HStack(spacing: 6) {
            if let current = value {
                DatePicker(label, selection: Binding(get: { current }, set: { value = $0 }), displayedComponents: components)
                    .datePickerStyle(.field)
                    .labelsHidden()
                KitIconButton(systemImage: "xmark.circle.fill", label: "Clear \(label.lowercased())") { value = nil }
            } else {
                Button(emptyLabel) { value = Date() }
                    .buttonStyle(KitButtonStyle(.secondary))
                    .accessibilityLabel("\(emptyLabel) (\(label.lowercased()))")
            }
        }
    }
}

/// The system checkbox, in the accent colour
struct KitCheckbox: View {
    @Environment(\.theme) private var theme
    let title: String
    @Binding var isOn: Bool
    /// Hide the text but keep it as the VoiceOver name (row tick boxes)
    var showsTitle = true

    var body: some View {
        Toggle(isOn: $isOn) {
            if showsTitle {
                Text(title).font(.system(size: 14)).foregroundStyle(theme.text200)
            } else {
                Text(title)
            }
        }
        .toggleStyle(.checkbox)
        .tint(theme.accent)
        .accessibilityLabel(title)
    }
}

/// The system radio group
struct KitRadioGroup<Value: Hashable>: View {
    @Environment(\.theme) private var theme
    let options: [(value: Value, label: String)]
    @Binding var selection: Value
    var label: String
    var horizontal = false

    var body: some View {
        Group {
            if horizontal {
                picker.horizontalRadioGroupLayout()
            } else {
                picker
            }
        }
        .font(.system(size: 14))
        .foregroundStyle(theme.text200)
        .tint(theme.accent)
        .accessibilityLabel(label)
    }

    private var picker: some View {
        Picker(label, selection: $selection) {
            ForEach(options.indices, id: \.self) { i in
                Text(options[i].label).tag(options[i].value)
            }
        }
        .pickerStyle(.radioGroup)
        .labelsHidden()
    }
}

/// A label above a field (web: text-sm font-medium text-gray-400)
struct KitFieldLabel<Content: View>: View {
    @Environment(\.theme) private var theme
    let text: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(text).font(.system(size: 14, weight: .medium)).foregroundStyle(theme.text400)
            content
        }
    }
}

/// The big title of an open item, edited in place (web: the click-to-edit h1 on a task page). Looks like a
/// heading until focused, then shows an accent underline. Return runs `onSubmit`; Escape runs `onCancel`.
struct KitTitleField: View {
    @Environment(\.theme) private var theme
    @FocusState private var focused: Bool
    let placeholder: String
    @Binding var text: String
    var onSubmit: (() -> Void)?
    var onCancel: (() -> Void)?
    /// True from outside moves the cursor here and selects the text (a new task)
    var focusRequest: Binding<Bool>?

    var body: some View {
        TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(theme.placeholder), axis: .vertical)
            .textFieldStyle(.plain)
            .font(.system(size: 24, weight: .bold))
            .foregroundStyle(theme.textPrimary)
            .lineLimit(1...4)
            .focused($focused)
            .onSubmit { onSubmit?() }
            .onExitCommand { onCancel?() }
            .onChange(of: focusRequest?.wrappedValue ?? false) { _, wanted in
                guard wanted else { return }
                focused = true
                focusRequest?.wrappedValue = false
                DispatchQueue.main.async { NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil) }
            }
            .padding(.bottom, 2)
            .overlay(alignment: .bottom) {
                Rectangle().fill(focused ? theme.accentHover : .clear).frame(height: 2)
            }
            .accessibilityLabel(placeholder)
    }
}

/// A date that must be chosen (a new event's day): the system date field in the kit's colours
struct KitDateField: View {
    @Binding var value: Date
    var label: String

    var body: some View {
        DatePicker(label, selection: $value, displayedComponents: .date)
            .datePickerStyle(.field)
            .labelsHidden()
            .accessibilityLabel(label)
    }
}

/// A time that must be chosen (an event's start and end)
struct KitTimeField: View {
    @Binding var value: Date
    var label: String

    var body: some View {
        DatePicker(label, selection: $value, displayedComponents: .hourAndMinute)
            .datePickerStyle(.field)
            .labelsHidden()
            .accessibilityLabel(label)
    }
}
