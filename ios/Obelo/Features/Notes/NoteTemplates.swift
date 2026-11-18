import SwiftUI

// Note templates (the web's Settings ▸ Notes ▸ Note templates): the list in Settings, the form to make or
// edit one, and the menu that starts a note from one. The logic is in Shared (`NoteTemplatesStore`).

/// The Note templates card in Settings ▸ Notes
struct NoteTemplatesCard: View {
    @Environment(\.theme) private var theme
    @State private var store = NoteTemplatesStore()
    @State private var editing: NoteTemplate?
    @State private var creating = false

    var body: some View {
        Card {
            CardHeader(title: "Note templates")
            VStack(alignment: .leading, spacing: 0) {
                Text("Starting points for new notes. They are yours to edit, delete and add to, and the same list shows on the web and in every app. You can also save an open note as a template.")
                    .font(.system(size: 12)).foregroundStyle(theme.textMuted)
                    .padding(.horizontal, 20).padding(.vertical, 14)
                if let error = store.error { Banner(kind: .error, text: error).padding(.horizontal, 16).padding(.bottom, 12) }
                if store.loaded && store.templates.isEmpty {
                    Text("No templates. Add one below.").font(.system(size: 13, weight: .regular)).italic()
                        .foregroundStyle(theme.textMuted).padding(.horizontal, 20).padding(.bottom, 14)
                }
                ForEach(store.templates) { t in
                    RowDivider()
                    Button { editing = t } label: {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(t.label).font(.system(size: 14)).foregroundStyle(theme.text200)
                                Text(NoteTemplatesStore.typeLabels[t.type] ?? t.type).font(.system(size: 12)).foregroundStyle(theme.textMuted)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(theme.textMuted)
                        }
                        .padding(.horizontal, 20).padding(.vertical, 11)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                RowDivider()
                SecondaryButton(title: "New template", systemImage: "plus") { creating = true }
                    .disabled(store.atLimit)
                    .padding(16)
            }
        }
        .task { await store.load() }
        .sheet(item: $editing) { NoteTemplateForm(store: store, template: $0) }
        .sheet(isPresented: $creating) { NoteTemplateForm(store: store, template: nil) }
    }
}

/// Making a template, or editing one (with Delete)
struct NoteTemplateForm: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    let store: NoteTemplatesStore
    let template: NoteTemplate?
    @State private var draft = NoteTemplateDraft()
    @State private var error: String?
    @State private var confirmDelete = false
    @State private var started = false

    var body: some View {
        FormSheet(title: template == nil ? "New template" : "Edit template", saveTitle: template == nil ? "Add" : "Save",
                  canSave: NoteTemplatesStore.problem(with: draft) == nil, error: error) {
            error = nil
            if let template { return await store.update(template.id, draft) ? true : fail() }
            return await store.create(draft) != nil ? true : fail()
        } content: {
            FormSection(label: "Name") { ThemedField(placeholder: "Standup", text: $draft.label) }
            FormSection(label: "Type") {
                SelectField(options: NoteTemplatesStore.types.map { ($0, NoteTemplatesStore.typeLabels[$0] ?? $0) }, selection: $draft.type)
            }
            FormSection(label: "Starting title") { ThemedField(placeholder: "Standup — ", text: $draft.title) }
            ToggleRow(title: "Use today's date as the title", subtitle: "The starting title above is then ignored", isOn: $draft.dateTitle)
            FormSection(label: "Starting text (Markdown)") {
                TextField("", text: $draft.content, prompt: Text("## Done\n- \n\n## Next\n- ").foregroundStyle(theme.placeholder), axis: .vertical)
                    .lineLimit(6...16)
                    .font(.system(size: 14, design: .monospaced)).foregroundStyle(theme.text100)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(theme.isDark ? theme.elevated : theme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(theme.border2, lineWidth: 1))
            }
            if template != nil {
                SecondaryButton(title: "Delete template", systemImage: "trash", tint: theme.red400) { confirmDelete = true }
            }
        }
        .onAppear { if !started { started = true; if let template { draft = NoteTemplateDraft(template) } } }
        .confirmationDialog("Delete this template?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let template { Task { await store.remove(template.id); dismiss() } }
            }
        }
    }

    private func fail() -> Bool { error = store.error; return false }
}

/// The "New note" button: a tap makes a blank note, a press-and-hold shows the person's templates.
/// With no templates it is a plain button.
struct NoteTemplateMenu<Label: View>: View {
    let templates: [NoteTemplate]
    let blank: () -> Void
    let start: (NoteTemplate) -> Void
    @ViewBuilder var label: Label

    var body: some View {
        if templates.isEmpty {
            Button(action: blank) { label }.buttonStyle(PressableStyle())
        } else {
            Menu {
                Button("Blank note", systemImage: "square.and.pencil", action: blank)
                Divider()
                ForEach(templates) { t in Button(t.label) { start(t) } }
            } label: { label } primaryAction: { blank() }
            .buttonStyle(PressableStyle())
        }
    }
}
