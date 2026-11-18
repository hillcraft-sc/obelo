import SwiftUI

/// Step two: the suggestion, editable, with the fields that suit the chosen type
struct CaptureSuggestionCard: View {
    @Environment(\.theme) private var theme
    let store: CaptureStore
    let save: () -> Void

    private var type: String { store.suggestion?.type ?? "note" }
    private var fields: Set<CaptureTypes.Field> { CaptureTypes.fields(for: type) }

    var body: some View {
        KitCard {
            header
            VStack(alignment: .leading, spacing: 16) {
                KitPillSelector(options: CaptureTypes.all.map { (value: $0, label: CaptureTypes.label($0)) },
                                selection: Binding(get: { type }, set: { store.suggestion?.type = $0 }), label: "Type")
                    .zIndex(0)
                if fields.contains(.url) {
                    KitFieldLabel(text: "URL *") { KitTextField(placeholder: "https://example.com", text: text(\.url)) }
                }
                KitFieldLabel(text: CaptureTypes.titleLabel(type)) { KitTextField(placeholder: CaptureTypes.titleLabel(type), text: text(\.title)) }
                if fields.contains(.content) {
                    KitFieldLabel(text: CaptureTypes.contentLabel(type)) {
                        KitTextArea(placeholder: CaptureTypes.contentLabel(type), text: text(\.content), minHeight: 72)
                    }
                }
                if fields.contains(.items) {
                    KitFieldLabel(text: "Items (one per line)") {
                        KitTextArea(placeholder: "Milk\nEggs\nBread", text: Binding(
                            get: { (store.suggestion?.items ?? []).joined(separator: "\n") },
                            set: { store.suggestion?.items = $0.components(separatedBy: "\n") }), minHeight: 110)
                    }
                }
                if fields.contains(.dueDate) {
                    Grid(alignment: .topLeading, horizontalSpacing: 16) {
                        GridRow {
                            KitFieldLabel(text: "Due date") {
                                KitOptionalDateField(components: .date, value: dueDate, label: "Due date", emptyLabel: "Set date")
                            }
                            KitFieldLabel(text: "Due time") {
                                KitOptionalDateField(components: .hourAndMinute, value: dueTime, label: "Due time", emptyLabel: "Set time")
                            }
                        }
                    }
                }
                if fields.contains(.priority) {
                    KitFieldLabel(text: "Priority") {
                        KitSelect(options: TasksStore.priorities.map { (value: $0, label: TasksStore.priorityLabels[$0] ?? $0) },
                                  selection: Binding(get: { store.suggestion?.priority ?? "none" }, set: { store.suggestion?.priority = $0 }),
                                  label: "Priority")
                            .frame(maxWidth: 200)
                    }
                }
                KitFieldLabel(text: "Tags") {
                    KitTagPicker(tags: Binding(get: { store.suggestion?.tags ?? [] }, set: { store.suggestion?.tags = $0 }),
                                 suggestions: store.allTags)
                }
                .zIndex(1)
                if fields.contains(.source) {
                    Grid(alignment: .topLeading, horizontalSpacing: 16) {
                        GridRow {
                            KitFieldLabel(text: "Source") { KitTextField(placeholder: "Book, podcast, article…", text: text(\.source)) }
                            KitFieldLabel(text: "Author") { KitTextField(placeholder: "Author name", text: text(\.author)) }
                        }
                    }
                }
                HStack(spacing: 12) {
                    Button("Save \(CaptureTypes.label(type))", action: save)
                        .buttonStyle(KitButtonStyle(.primary, busy: store.saving, fullWidth: true))
                        .keyboardShortcut(.return, modifiers: .command)
                        .disabled(!store.canSave)
                        .help("⌘Return")
                    Button("Discard") { Task { await store.discard() } }
                        .buttonStyle(KitButtonStyle(.secondary))
                }
                .padding(.top, 4)
            }
            .padding(20)
        }
    }

    // ── Header: the type, how sure the server is, and what you typed ────────

    private var header: some View {
        let confidence = store.suggestion?.confidence
        return KitCardHeader(title: "\(CaptureTypes.icon(type)) \(CaptureTypes.label(type))",
                             badge: confidence == "low" ? "Low confidence — check fields" : confidence == "medium" ? "Medium confidence" : nil,
                             badgeTone: confidence == "low" ? .warn : .info) {
            Text("\u{201C}\(store.raw)\u{201D}")
                .font(.system(size: 12)).italic().foregroundStyle(theme.textMuted)
                .lineLimit(1).frame(maxWidth: 200, alignment: .trailing)
                .opacity(store.raw.isEmpty ? 0 : 1)
        }
    }

    // ── Bindings into the suggestion ────────────────────────────────────────

    private func text(_ keyPath: WritableKeyPath<CaptureSuggestion, String?>) -> Binding<String> {
        Binding(get: { store.suggestion?[keyPath: keyPath] ?? "" },
                set: { store.suggestion?[keyPath: keyPath] = $0.isEmpty ? nil : $0 })
    }

    private var dueDate: Binding<Date?> {
        Binding(get: { store.suggestion?.dueDate.map { Fmt.localDate($0) } },
                set: { store.suggestion?.dueDate = $0.map { Fmt.ymd($0) } })
    }

    private var dueTime: Binding<Date?> {
        Binding(get: { store.suggestion?.dueTime.map { Fmt.date(fromHHMM: $0) } },
                set: { store.suggestion?.dueTime = $0.map { Fmt.hhmm(from: $0) } })
    }
}
