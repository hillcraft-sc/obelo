import SwiftUI

// ── Swipe row ────────────────────────────────────────────────────────────────
// The web's mobile swipe gestures on task/reminder/routine rows: swipe right reveals a green
// "Complete", swipe left a red "Delete"; past the threshold the action fires.

struct SwipeRow<Content: View>: View {
    @Environment(\.theme) private var theme
    var onComplete: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil
    var completeLabel = "Complete"
    var completeIcon = "checkmark"
    var completeColor = StatusPalette.tailwind.green700
    var deleteLabel = "Delete"
    var deleteIcon = "trash"
    var deleteColor = StatusPalette.tailwind.red700
    var transparent = false
    @ViewBuilder var content: Content

    @State private var offset: CGFloat = 0
    @State private var horizontal: Bool?
    private let threshold: CGFloat = 90

    var body: some View {
        ZStack {
            if offset > 0, onComplete != nil {
                HStack(spacing: 8) {
                    Image(systemName: completeIcon).font(.system(size: 16, weight: .bold))
                    Text(completeLabel).font(.system(size: 14, weight: .semibold))
                    Spacer()
                }
                .foregroundStyle(.white).padding(.leading, 20)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(completeColor)
                .opacity(min(1, offset / threshold))
            }
            if offset < 0, onDelete != nil {
                HStack(spacing: 8) {
                    Spacer()
                    Text(deleteLabel).font(.system(size: 14, weight: .semibold))
                    Image(systemName: deleteIcon).font(.system(size: 16))
                }
                .foregroundStyle(.white).padding(.trailing, 20)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(deleteColor)
                .opacity(min(1, -offset / threshold))
            }
            content
                .background(transparent ? .clear : theme.surface)
                .offset(x: offset)
        }
        .clipped()
        .simultaneousGesture(
            DragGesture(minimumDistance: 14)
                .onChanged { value in
                    if horizontal == nil {
                        horizontal = abs(value.translation.width) > abs(value.translation.height) * 1.4
                    }
                    guard horizontal == true else { return }
                    var x = value.translation.width
                    if x > 0, onComplete == nil { x = 0 }
                    if x < 0, onDelete == nil { x = 0 }
                    offset = x
                }
                .onEnded { _ in
                    defer { horizontal = nil }
                    guard horizontal == true else { return }
                    if offset > threshold, let onComplete {
                        Haptics.success()
                        withAnimation(.easeOut(duration: 0.2)) { offset = 500 }
                        onComplete()
                    } else if offset < -threshold, let onDelete {
                        Haptics.medium()
                        withAnimation(.easeOut(duration: 0.2)) { offset = -500 }
                        onDelete()
                    } else {
                        withAnimation(.spring(duration: 0.3)) { offset = 0 }
                    }
                }
        )
    }
}

// ── Tag editing ──────────────────────────────────────────────────────────────

/// Comma-separated tags with suggestions from the user's existing tags (the web's tag picker)
/// The web's tag picker (notes/_tag-picker.ejs, public/js/tag-picker.js): the chosen tags are pills
/// inside one box, followed by "Add a tag…". While typing there, a list of the other tags drops down
/// (matching what's typed), with "Create #…" for a new one. Return or a comma adds the top option.
struct TagsField: View {
    @Environment(\.theme) private var theme
    @Binding var tags: [String]
    var suggestions: [String] = []
    @State private var draft = ""
    @FocusState private var focused: Bool
    /// The list stays up a moment after the field loses focus: tapping it on iPhone closes the
    /// keyboard first, and the tap still has to land on the tag
    @State private var showMenu = false

    private struct Option: Hashable { let value: String; let create: Bool }

    /// Tags not chosen yet that contain what's typed, plus "Create #…" for a new one (as the web)
    private var options: [Option] {
        let q = Fmt.tags(from: draft).first ?? ""
        var list = suggestions.filter { !tags.contains($0) && (q.isEmpty || $0.contains(q)) }
            .prefix(50).map { Option(value: $0, create: false) }
        if !q.isEmpty && !suggestions.contains(q) && !tags.contains(q) { list.insert(Option(value: q, create: true), at: 0) }
        return list
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            FlowLayout(spacing: 6) {
                ForEach(tags, id: \.self) { tag in
                    HStack(spacing: 4) {
                        Text("#\(tag)").font(.system(size: 12)).foregroundStyle(theme.accentTextLight)
                        Button { withAnimation(.easeOut(duration: 0.12)) { tags.removeAll { $0 == tag } } } label: {
                            Text("×").font(.system(size: 13)).foregroundStyle(theme.accentTextLight.opacity(0.8))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove tag \(tag)")
                    }
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(theme.accent.opacity(0.2), in: Capsule())
                    .overlay(Capsule().stroke(theme.accent.opacity(0.3), lineWidth: 1))
                }
                TextField("", text: $draft, prompt: Text("Add a tag…").foregroundStyle(theme.placeholder))
                    .font(.system(size: 14))
                    .foregroundStyle(theme.text100)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focused)
                    .onSubmit { addTop(); focused = true }
                    .onChange(of: draft) { _, new in if new.hasSuffix(",") { draft = String(new.dropLast()); addTop() } }
                    .frame(width: 150)
            }
            .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(theme.elevated, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(focused ? theme.accent : theme.border2, lineWidth: focused ? 2 : 1))
            .contentShape(Rectangle())
            .onTapGesture { focused = true }

            if showMenu { menu }

            Text("Pick a tag from the list, or type a new one and press Enter.")
                .font(.system(size: 12)).foregroundStyle(theme.textMuted)
        }
        .animation(.easeOut(duration: 0.12), value: showMenu)
        #if DEBUG
        // Testing: `-focusTags YES` focuses the tag box on open, to see the list
        .task { if UserDefaults.standard.bool(forKey: "focusTags") { try? await Task.sleep(for: .seconds(1)); focused = true } }
        #endif
        .onChange(of: focused) { _, isFocused in
            if isFocused { showMenu = true; return }
            Task {
                try? await Task.sleep(for: .milliseconds(300))
                if !focused { showMenu = false }
            }
        }
    }

    /// The drop-down list of tags
    private var menu: some View {
        let opts = options
        return Group {
            if opts.isEmpty {
                Text(suggestions.isEmpty ? "No tags yet. Type one and press Enter." : "No matching tags. Press Enter to create one.")
                    .font(.system(size: 12)).foregroundStyle(theme.textMuted)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(opts.enumerated()), id: \.element) { i, opt in
                            Button { add(opt.value); focused = true } label: {
                                Text(opt.create ? "Create #\(opt.value)" : "#\(opt.value)")
                                    .font(.system(size: 14)).italic(opt.create)
                                    .foregroundStyle(i == 0 ? theme.textPrimary : theme.text300)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 12).padding(.vertical, 6)
                                    .background(i == 0 ? theme.elevated : .clear)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 240)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(theme.border2, lineWidth: 1))
    }

    /// Return or a comma: the top option, as on the web (nothing when the box is empty)
    private func addTop() {
        guard !draft.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        if let first = options.first { add(first.value) } else { add(draft) }
    }

    private func add(_ raw: String) {
        for t in Fmt.tags(from: raw) where !tags.contains(t) { tags.append(t) }
        draft = ""
    }
}

// ── Optional date / time pickers ─────────────────────────────────────────────

/// "YYYY-MM-DD" optional date, with a toggle to clear
struct OptionalDateField: View {
    @Environment(\.theme) private var theme
    @Binding var ymd: String?
    var allowClear = true

    var body: some View {
        HStack {
            if ymd != nil {
                DatePicker("", selection: Binding(
                    get: { Fmt.localDate(ymd) },
                    set: { ymd = Fmt.ymd($0) }
                ), displayedComponents: .date)
                .labelsHidden()
                Spacer()
                if allowClear {
                    Button("Clear") { ymd = nil }.font(.system(size: 13)).foregroundStyle(theme.textMuted)
                }
            } else {
                Button { ymd = Fmt.ymd(.now) } label: {
                    Label("Add date", systemImage: "calendar").font(.system(size: 14)).foregroundStyle(theme.text400)
                }
                Spacer()
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .frame(minHeight: 44)
        .background(theme.isDark ? theme.elevated : theme.surface, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.border2, lineWidth: 1))
    }
}

/// "HH:MM" optional time
struct OptionalTimeField: View {
    @Environment(\.theme) private var theme
    @Binding var hhmm: String?
    var allowClear = true

    var body: some View {
        HStack {
            if hhmm != nil {
                DatePicker("", selection: Binding(
                    get: { Fmt.date(fromHHMM: hhmm) },
                    set: { hhmm = Fmt.hhmm(from: $0) }
                ), displayedComponents: .hourAndMinute)
                .labelsHidden()
                Spacer()
                if allowClear {
                    Button("Clear") { hhmm = nil }.font(.system(size: 13)).foregroundStyle(theme.textMuted)
                }
            } else {
                Button { hhmm = "09:00" } label: {
                    Label("Add time", systemImage: "clock").font(.system(size: 14)).foregroundStyle(theme.text400)
                }
                Spacer()
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .frame(minHeight: 44)
        .background(theme.isDark ? theme.elevated : theme.surface, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.border2, lineWidth: 1))
    }
}

/// A themed on/off row (the web's checkbox + label)
struct ToggleRow: View {
    @Environment(\.theme) private var theme
    let title: String
    var subtitle: String? = nil
    @Binding var isOn: Bool
    var body: some View {
        // Label on the left and the switch on the right, on iPhone and Mac alike
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .medium)).foregroundStyle(theme.text200)
                if let subtitle { Text(subtitle).font(.system(size: 12)).foregroundStyle(theme.textMuted) }
            }
            Spacer(minLength: 12)
            Toggle(title, isOn: $isOn).labelsHidden().tint(theme.accent)
        }
    }
}

/// Modal form chrome: themed sheet with Cancel / Save
struct FormSheet<Content: View>: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    let title: String
    var saveTitle = "Save"
    var canSave = true
    var error: String? = nil
    let save: () async -> Bool
    @ViewBuilder var content: Content
    @State private var saving = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let error { Banner(kind: .error, text: error) }
                    content
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.immediately)
            .background(theme.page)
            .themedNavBar(theme, title: title)
            .keyboardDoneButton()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(theme.text400)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if saving { ProgressView() } else {
                        Button(saveTitle) {
                            saving = true
                            Task {
                                if await save() { dismiss() }
                                saving = false
                            }
                        }
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                    }
                }
            }
        }
        .presentationBackground(theme.page)
    }
}
