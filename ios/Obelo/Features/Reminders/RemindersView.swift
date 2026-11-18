import SwiftUI

// Reminders — views/reminders/index.ejs, show.ejs and form.ejs.

struct RemindersView: View {
    @Environment(AppState.self) private var app
    @Environment(Toast.self) private var toast
    @Environment(\.theme) private var theme

    struct Response: Decodable {
        let reminders: [ReminderItem]
        let tags: [String]
        let counts: Counts
        struct Counts: Decodable { let overdue: Int; let today: Int }
    }

    @State private var view = "upcoming"
    @State private var tag: String?
    @State private var data: Response?
    @State private var reminders: [ReminderItem] = []
    @State private var error: String?
    @State private var showNew = false

    var body: some View {
        Page(refresh: load) {
            PageHeader(title: "Reminders", subtitle: "One-off nudges at a set date and time.", pageName: true) {
                PrimaryButton(title: "New reminder", systemImage: "plus") { showNew = true }
            }
            SectionTabs(tabs: [
                SectionTab(key: "upcoming", label: "Upcoming"),
                SectionTab(key: "today", label: "Today", badge: data?.counts.today),
                SectionTab(key: "overdue", label: "Overdue", badge: data?.counts.overdue, warn: true),
                SectionTab(key: "completed", label: "Completed"),
            ], selection: $view)
            TagFilter(tags: data?.tags ?? [], selected: $tag)
            if let error { Banner(kind: .error, text: error) }
            Card {
                if data == nil {
                    ProgressView().frame(maxWidth: .infinity).padding(40)
                } else if reminders.isEmpty {
                    EmptyRow(text: emptyText, action: emptyAction)
                } else {
                    ForEach(Array(reminders.enumerated()), id: \.element.id) { i, r in
                        if i > 0 { RowDivider() }
                        SwipeRow(onComplete: r.completed ? nil : { complete(r) },
                                 onDelete: r.completed ? nil : { snooze(r, "1hour") },
                                 deleteLabel: "Snooze 1h", deleteIcon: "clock", deleteColor: Color(hex: "#b45309")) {
                            ReminderRow(reminder: r, hour12: app.hour12) {
                                r.completed ? restore(r) : complete(r)
                            }
                            .contextMenu {
                                if !r.completed {
                                    Button("Snooze 15 minutes", systemImage: "clock") { snooze(r, "15min") }
                                    Button("Snooze 1 hour", systemImage: "clock") { snooze(r, "1hour") }
                                    Button("Snooze until tomorrow", systemImage: "sunrise") { snooze(r, "tomorrow") }
                                }
                                Button("Delete", systemImage: "trash", role: .destructive) { delete(r) }
                            }
                        }
                    }
                }
            }
        }
        .task(id: "\(view)|\(tag ?? "")|\(app.dataVersion)") { await load() }
        .onNewItem("reminders") { showNew = true }
        .sheet(isPresented: $showNew) { ReminderForm(reminder: nil) { Task { await load() } } }
    }

    /// Same wording as views/reminders/index.ejs
    private var emptyText: String {
        if tag != nil { return "No reminders match this filter." }
        return switch view {
        case "today": "Nothing due today."
        case "overdue": "Nothing overdue."
        case "completed": "No completed reminders yet."
        default: "No upcoming reminders yet."
        }
    }

    private var emptyAction: EmptyAction? {
        if tag != nil { return EmptyAction(label: "Clear filter") { tag = nil } }
        return view == "completed" ? nil : EmptyAction(label: "New reminder") { showNew = true }
    }

    private func load() async {
        do {
            let r: Response = try await APIClient.shared.get("/reminders", query: ["view": view, "tag": tag])
            data = r
            withAnimation(.easeOut(duration: 0.15)) { reminders = r.reminders }
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    private func remove(_ r: ReminderItem) {
        withAnimation(.easeOut(duration: 0.25)) { reminders.removeAll { $0.id == r.id } }
    }

    private func complete(_ r: ReminderItem) {
        remove(r)
        toast.run { try await APIClient.shared.post("/reminders/\(r.id)/complete"); app.dataChanged() }
    }

    private func restore(_ r: ReminderItem) {
        remove(r)
        toast.run { try await APIClient.shared.post("/reminders/\(r.id)/restore"); app.dataChanged() }
    }

    private func snooze(_ r: ReminderItem, _ duration: String) {
        remove(r)
        toast.run {
            try await APIClient.shared.post("/reminders/\(r.id)/snooze", ["duration": duration])
            toast.show(["15min": "Snoozed 15 minutes", "1hour": "Snoozed 1 hour"][duration] ?? "Snoozed until tomorrow")
            app.dataChanged()
        }
    }

    private func delete(_ r: ReminderItem) {
        remove(r)
        toast.run { try await APIClient.shared.delete("/reminders/\(r.id)"); app.dataChanged() }
    }
}

/// reminders/_row.ejs
struct ReminderRow: View {
    @Environment(\.theme) private var theme
    let reminder: ReminderItem
    let hour12: Bool
    let toggle: () -> Void

    private var dueColor: Color {
        if reminder.completed { return theme.textMuted }
        return switch reminder.dueState {
        case "overdue": theme.red400
        case "today": theme.green400
        default: theme.text400
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            CompleteCircle(done: reminder.completed, action: toggle)
            PriorityIcon(priority: reminder.priority)
            NavigationLink(value: Route.reminder(reminder.id)) {
                HStack(spacing: 6) {
                    Text(reminder.title)
                        .font(.system(size: 14))
                        .strikethrough(reminder.completed, color: theme.textMuted)
                        .foregroundStyle(reminder.completed ? theme.textMuted : theme.text200)
                        .lineLimit(1)
                    if reminder.recurring { Text("↻").font(.system(size: 10)).foregroundStyle(theme.textMuted) }
                    Spacer(minLength: 4)
                    Text(Fmt.due(reminder.dueDate, reminder.dueTime, hour12: hour12))
                        .font(.system(size: 12, weight: reminder.dueState == "overdue" ? .medium : .regular))
                        .foregroundStyle(dueColor)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }
}

struct ReminderDetailView: View {
    @Environment(AppState.self) private var app
    @Environment(Toast.self) private var toast
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    let id: Int

    @State private var reminder: ReminderItem?
    @State private var error: String?
    @State private var editing = false
    @State private var confirmDelete = false

    struct R: Decodable { let reminder: ReminderItem }

    var body: some View {
        Loadable(value: reminder, error: error, retry: load) { r in
            Page(refresh: load) {
                Card(padding: 20) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 10) {
                            Image(systemName: "bell.fill").foregroundStyle(r.dueState == "overdue" ? theme.red400 : theme.accentText)
                            Text(r.title).font(.system(size: 24, weight: .bold)).foregroundStyle(theme.textPrimary)
                        }
                        FlowLayout(spacing: 12) {
                            Label(Fmt.due(r.dueDate, r.dueTime, hour12: app.hour12), systemImage: "calendar")
                                .foregroundStyle(r.dueState == "overdue" ? theme.red400 : r.dueState == "today" ? theme.green400 : theme.text400)
                            if r.priority != "none" {
                                HStack(spacing: 6) {
                                    Dot(color: theme.priorityDot(r.priority))
                                    Text("\(Fmt.priorityLabel(r.priority)) priority").foregroundStyle(theme.text400)
                                }
                            }
                            if r.recurring { Label(r.recurLabel, systemImage: "repeat").foregroundStyle(theme.text400) }
                            if r.completed { Label("Completed", systemImage: "checkmark.circle").foregroundStyle(theme.green400) }
                        }
                        .font(.system(size: 14))
                        if let at = r.reminderAt, !r.completed {
                            Text("Alert at \(at.formatted(date: .abbreviated, time: .shortened))")
                                .font(.system(size: 12)).foregroundStyle(theme.textMuted)
                        }
                        if !r.tags.isEmpty { FlowLayout(spacing: 6) { ForEach(r.tags, id: \.self) { TagPill(tag: $0) } } }
                        if !r.notes.isEmpty { RowDivider(); MarkdownView(text: r.notes) }
                    }
                }
                if !r.completed {
                    Card(padding: 16) {
                        Text("SNOOZE").font(.system(size: 12, weight: .semibold)).tracking(0.6).foregroundStyle(theme.textMuted)
                            .padding(.bottom, 10)
                        HStack(spacing: 8) {
                            SecondaryButton(title: "15 min") { snooze("15min") }
                            SecondaryButton(title: "1 hour") { snooze("1hour") }
                            SecondaryButton(title: "Tomorrow") { snooze("tomorrow") }
                        }
                    }
                }
                HStack(spacing: 8) {
                    if r.completed {
                        SecondaryButton(title: "Restore", systemImage: "arrow.uturn.backward") { act("restore") }
                    } else {
                        PrimaryButton(title: "Mark complete", systemImage: "checkmark") { act("complete", leave: true) }
                    }
                    Spacer()
                    SecondaryButton(title: "Delete", systemImage: "trash", tint: theme.red400) { confirmDelete = true }
                }
            }
        }
        .themedNavBar(theme, title: "Reminders")
        .toolbar { ToolbarItem(placement: .primaryAction) { Button("Edit") { editing = true }.disabled(reminder == nil) } }
        .task { await load() }
        .sheet(isPresented: $editing) {
            if let reminder { ReminderForm(reminder: reminder) { Task { await load(); app.dataChanged() } } }
        }
        .confirmationDialog("Delete this reminder?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                toast.run { try await APIClient.shared.delete("/reminders/\(id)"); app.dataChanged(); dismiss() }
            }
        }
    }

    private func load() async {
        do { reminder = (try await APIClient.shared.get("/reminders/\(id)") as R).reminder }
        catch { self.error = error.localizedDescription }
    }

    private func act(_ action: String, leave: Bool = false) {
        toast.run {
            try await APIClient.shared.post("/reminders/\(id)/\(action)")
            app.dataChanged()
            if leave { dismiss() } else { await load() }
        }
    }

    private func snooze(_ duration: String) {
        toast.run {
            try await APIClient.shared.post("/reminders/\(id)/snooze", ["duration": duration])
            toast.show("Snoozed")
            app.dataChanged()
            await load()
        }
    }
}

/// reminders/form.ejs
struct ReminderForm: View {
    let reminder: ReminderItem?
    let saved: () -> Void

    @State private var title = ""
    @State private var notes = ""
    @State private var dueDate: String? = Fmt.ymd(.now)
    @State private var dueTime: String? = "09:00"
    @State private var offset = 0
    @State private var priority = "none"
    @State private var tags: [String] = []
    @State private var recurring = false
    @State private var recurRule = "daily"
    @State private var allTags: [String] = []
    @State private var error: String?
    @State private var loaded = false

    var body: some View {
        FormSheet(title: reminder == nil ? "New Reminder" : "Edit Reminder", saveTitle: reminder == nil ? "Create" : "Save",
                  canSave: !title.trimmingCharacters(in: .whitespaces).isEmpty, error: error, save: save) {
            FormSection(label: "Title") { ThemedField(placeholder: "Remind me to…", text: $title) }
            FormSection(label: "Date") { OptionalDateField(ymd: $dueDate, allowClear: false) }
            FormSection(label: "Time") { OptionalTimeField(hhmm: $dueTime, allowClear: false) }
            HStack(spacing: 12) {
                FormSection(label: "Alert") { SelectField(options: Fmt.reminderOffsets, selection: $offset) }
                FormSection(label: "Priority") {
                    SelectField(options: Fmt.priorities.map { ($0, Fmt.priorityLabel($0)) }, selection: $priority)
                }
            }
            FormSection(label: "Notes") { ThemedField(placeholder: "Optional", text: $notes, axis: .vertical).lineLimit(3...10) }
            FormSection(label: "Tags") { TagsField(tags: $tags, suggestions: allTags) }
            ToggleRow(title: "Repeat", isOn: $recurring)
            if recurring { SelectField(options: Fmt.recurRules, selection: $recurRule) }
        }
        .task {
            guard !loaded else { return }
            loaded = true
            if let reminder {
                // The list payload has no offset; the detail one does
                struct R: Decodable { let reminder: ReminderItem }
                let full = ((try? await APIClient.shared.get("/reminders/\(reminder.id)")) as R?)?.reminder ?? reminder
                title = full.title; notes = full.notes; dueDate = full.dueDate ?? Fmt.ymd(.now); dueTime = full.dueTime ?? "09:00"
                priority = full.priority; tags = full.tags; recurring = full.recurring; recurRule = full.recurRule ?? "daily"
                offset = Fmt.reminderOffsets.map(\.0).contains(full.reminderOffset ?? 0) ? (full.reminderOffset ?? 0) : 0
            }
            struct T: Decodable { let tags: [String] }
            allTags = ((try? await APIClient.shared.get("/tags")) as T?)?.tags ?? []
        }
    }

    private func save() async -> Bool {
        let body: [String: Any] = [
            "title": title, "notes": notes, "dueDate": dueDate ?? "", "dueTime": dueTime ?? "",
            "reminderOffset": offset, "priority": priority, "tags": tags, "recurring": recurring, "recurRule": recurRule,
        ]
        do {
            if let reminder { try await APIClient.shared.post("/reminders/\(reminder.id)", body, method: "PUT") }
            else { try await APIClient.shared.post("/reminders", body) }
            saved()
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }
}
