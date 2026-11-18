#if DEBUG
import AppKit
import SwiftUI

/// The kit gallery (Debug ▸ Kit Gallery, ⌥⌘G, or launch with `-openGallery YES`): every component of the
/// Mac design kit, in any of the twelve themes, with the states it can be in. Hover, pressed and focus are
/// live: point at, click or tab to a component to see them. `-galleryTheme ctp-latte` picks the theme on launch.
/// A screen may only use components that appear here.
struct KitGallery: View {
    @State private var themeID = UserDefaults.standard.string(forKey: "galleryTheme") ?? "dark"

    /// Resolved the way the app does it, so the Catppuccin themes get their own status colours
    private var theme: Theme {
        let isDark = Theme.builtIn.first { $0.id == themeID }?.isDark ?? true
        return Theme.resolve(Appearance(theme: themeID, isDark: isDark, customAccent: "#2563eb", customBase: "dark"))
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header.id(0)
                    LayoutSection().id(1)
                    ButtonsSection().id(2)
                    TabsSection().id(3)
                    FieldsSection().id(4)
                    TagsSection().id(5)
                    RowsSection().id(6)
                    FeedbackSection().id(7)
                    SplitSection().id(8)
                    SignInPiecesSection().id(9)
                    DashboardPiecesSection().id(10)
                    CapturePiecesSection().id(11)
                    NotesPiecesSection().id(12)
                    HandwritingAttachmentsSection().id(13)
                    ChartsSection().id(14)
                    ReorderSection().id(15)
                    TableSection().id(16)
                    CalendarSection().id(17)
                    AnalyticsSection().id(18)
                    ChatSection().id(19)
                    SearchSection().id(20)
                    HelpSection().id(21)
                    SettingsSection().id(22)
                }
                .padding(28)
                .frame(maxWidth: 900, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .task { await snapshotIfAsked(proxy) }
        }
        .background(theme.page)
        .environment(\.theme, theme)
        .preferredColorScheme(theme.colorScheme)
        .tint(theme.accent)
        .frame(minWidth: 760, minHeight: 600)
    }

    /// Testing: `-gallerySnapshots <folder>` writes one PNG per section of this window's own drawing (not a
    /// screen capture, so other windows don't matter), then quits.
    private func snapshotIfAsked(_ proxy: ScrollViewProxy) async {
        guard let folder = UserDefaults.standard.string(forKey: "gallerySnapshots") else { return }
        try? await Task.sleep(for: .seconds(1.5))
        guard let view = NSApp.windows.first(where: { $0.title == "Kit Gallery" })?.contentView else { NSApp.terminate(nil); return }
        for i in 0...22 {
            proxy.scrollTo(i, anchor: .top)
            try? await Task.sleep(for: .seconds(0.8))
            if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?
                    .write(to: URL(fileURLWithPath: folder).appendingPathComponent("gallery-\(themeID)-\(i).png"))
            }
        }
        NSApp.terminate(nil)
    }

    private var header: some View {
        KitPageHeading(title: "Kit gallery", description: "Every component of the Mac design kit, in the theme you pick.") {
            KitSelect(options: Theme.builtIn.map { ($0.id, Theme.labels[$0.id]?.label ?? $0.id) },
                      selection: $themeID, label: "Theme")
                .frame(width: 220)
        }
    }
}

/// One titled block of the gallery
private struct GallerySection<Content: View>: View {
    let title: String
    var note: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            KitGroupLabel(text: title)
            KitCard {
                VStack(alignment: .leading, spacing: 18) { content }.padding(16)
            }
            if let note { NoteText(note) }
        }
    }
}

private struct NoteText: View {
    @Environment(\.theme) private var theme
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(text).font(.system(size: 12)).foregroundStyle(theme.textMuted) }
}

private struct Labelled<Content: View>: View {
    @Environment(\.theme) private var theme
    let label: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 11)).foregroundStyle(theme.textMuted)
            content
        }
    }
}

// MARK: Layout

private struct LayoutSection: View {
    @State private var empty = 0
    var body: some View {
        GallerySection(title: "Page heading, card, group label, empty state",
                note: "Page widths: lists 768, calendar 1024, forms 576 (KitWidth).") {
            KitPageHeading(title: "Tasks", description: "Everything you plan to do, from inbox to done.") {
                Button("New task") {}.buttonStyle(KitButtonStyle(.primary))
            }
            KitCard {
                KitCardHeader(title: "Card header", detail: "with detail") {
                    Button("Link") {}.buttonStyle(KitButtonStyle(.ghost, small: true))
                }
                Text("Card body").padding(16).font(.system(size: 14))
            }
            KitGroupLabel(text: "Group label")
            KitCard {
                KitEmptyState(message: "No inbox tasks yet.", actionLabel: "New task") { empty += 1 }
            }
            KitCard { KitEmptyState(message: "Nothing due today.") }
        }
    }
}

// MARK: Buttons

private struct ButtonsSection: View {
    var body: some View {
        GallerySection(title: "Buttons",
                note: "Return and Escape come from .keyboardShortcut(.defaultAction / .cancelAction) on the button.") {
            Labelled(label: "Normal (hover and press to see the other states)") {
                HStack(spacing: 10) {
                    Button("Primary") {}.buttonStyle(KitButtonStyle(.primary))
                    Button("Secondary") {}.buttonStyle(KitButtonStyle(.secondary))
                    Button("Danger") {}.buttonStyle(KitButtonStyle(.danger))
                    Button("Ghost") {}.buttonStyle(KitButtonStyle(.ghost))
                }
            }
            Labelled(label: "Disabled") {
                HStack(spacing: 10) {
                    Button("Primary") {}.buttonStyle(KitButtonStyle(.primary))
                    Button("Secondary") {}.buttonStyle(KitButtonStyle(.secondary))
                    Button("Danger") {}.buttonStyle(KitButtonStyle(.danger))
                    Button("Ghost") {}.buttonStyle(KitButtonStyle(.ghost))
                }
                .disabled(true)
            }
            Labelled(label: "Small") {
                HStack(spacing: 10) {
                    Button("Apply") {}.buttonStyle(KitButtonStyle(.primary, small: true))
                    Button("Secondary") {}.buttonStyle(KitButtonStyle(.secondary, small: true))
                    Button("Cancel") {}.buttonStyle(KitButtonStyle(.ghost, small: true))
                }
            }
            Labelled(label: "Action menu (opens a list of actions: the row's Snooze)") {
                HStack(spacing: 10) {
                    KitActionMenu(title: "Snooze") {
                        Button("15 minutes") {}
                        Button("1 hour") {}
                        Button("Tomorrow") {}
                    }
                    KitActionMenu(title: "Sort", systemImage: "arrow.up.arrow.down", small: false) {
                        Button("By date") {}
                        Button("By priority") {}
                    }
                }
            }
            Labelled(label: "Icon buttons (tooltip on hover)") {
                HStack(spacing: 4) {
                    KitIconButton(systemImage: "plus", label: "Add") {}
                    KitIconButton(systemImage: "trash", label: "Delete", destructive: true) {}
                    KitIconButton(systemImage: "trash", label: "Delete (disabled)") {}.disabled(true)
                }
            }
        }
    }
}

// MARK: Tabs

private struct TabsSection: View {
    @State private var selection = "inbox"
    var body: some View {
        GallerySection(title: "Underlined tabs") {
            KitTabs(tabs: [
                KitTab(id: "inbox", label: "Inbox", badge: 4),
                KitTab(id: "today", label: "Today", badge: 2),
                KitTab(id: "upcoming", label: "Upcoming"),
                KitTab(id: "all", label: "All"),
                KitTab(id: "done", label: "Completed"),
                KitTab(id: "slipping", label: "Slipping", badge: 3, warn: true),
            ], selection: $selection)
        }
    }
}

// MARK: Fields

private struct FieldsSection: View {
    @State private var text = ""
    @State private var filled = "Buy oat milk"
    @State private var error = "x"
    @State private var disabled = "Locked"
    @State private var search = ""
    @State private var title = "Send the quarterly report"
    @State private var area = ""
    @State private var areaFilled = "Notes in **Markdown**.\nSecond line."
    @State private var number = 2
    @State private var select = "inbox"
    @State private var priority = "none"
    @State private var due: Date? = nil
    @State private var dueSet: Date? = Date()
    @State private var time: Date? = nil
    @State private var timeSet: Date? = Date()
    @State private var on = true
    @State private var off = false
    @State private var radio = "each"

    private let statuses: [(value: String, label: String)] = [
        ("inbox", "Inbox"), ("today", "Today"), ("in-progress", "In Progress"), ("done", "Done"), ("archived", "Archived"),
    ]
    private let priorities: [(value: String, label: String)] = [
        ("none", "None"), ("low", "Low"), ("medium", "Medium"), ("high", "High"),
    ]

    var body: some View {
        GallerySection(title: "Fields",
                note: "These wrap the macOS controls (text field, pop-up menu, date picker, checkbox, radio group) in the theme's colours. The date picker's own colours come from the system.") {
            Labelled(label: "Text field: empty, filled, error, disabled (click one to see the focus ring)") {
                VStack(spacing: 8) {
                    KitTextField(placeholder: "Quick-add a task and press Enter...", text: $text)
                    KitTextField(placeholder: "Title", text: $filled)
                    KitTextField(placeholder: "Title", text: $error, isError: true)
                    KitTextField(placeholder: "Title", text: $disabled).disabled(true)
                }
            }
            Labelled(label: "Title field (click to edit)") { KitTitleField(placeholder: "Title", text: $title) }
            Labelled(label: "Search field") { KitSearchField(placeholder: "Search tasks...", text: $search) }
            Labelled(label: "Text area: empty, filled") {
                VStack(spacing: 8) {
                    KitTextArea(placeholder: "Notes", text: $area)
                    KitTextArea(placeholder: "Notes", text: $areaFilled, minHeight: 56)
                }
            }
            Labelled(label: "Number field with stepper") {
                HStack {
                    Text("Every").font(.system(size: 14))
                    KitNumberField(value: $number, range: 1...99, label: "Repeat every")
                    Text("days").font(.system(size: 14))
                }
            }
            Labelled(label: "Select: field, compact (as in a row), disabled") {
                HStack(spacing: 14) {
                    KitSelect(options: priorities, selection: $priority, label: "Priority").frame(width: 160)
                    KitSelect(options: statuses, selection: $select, label: "Status", compact: true)
                    KitSelect(options: priorities, selection: $priority, label: "Priority").frame(width: 160).disabled(true)
                }
            }
            Labelled(label: "Date and time: empty, set") {
                HStack(spacing: 14) {
                    KitOptionalDateField(components: .date, value: $due, label: "Due date", emptyLabel: "Set date")
                    KitOptionalDateField(components: .date, value: $dueSet, label: "Due date", emptyLabel: "Set date")
                    KitOptionalDateField(components: .hourAndMinute, value: $time, label: "Due time", emptyLabel: "Set time")
                    KitOptionalDateField(components: .hourAndMinute, value: $timeSet, label: "Due time", emptyLabel: "Set time")
                }
            }
            Labelled(label: "Checkbox: on, off, disabled") {
                HStack(spacing: 18) {
                    KitCheckbox(title: "Repeat", isOn: $on)
                    KitCheckbox(title: "Repeat", isOn: $off)
                    KitCheckbox(title: "Repeat", isOn: $on).disabled(true)
                }
            }
            Labelled(label: "Radio group") {
                KitRadioGroup(options: [("each", "Each day of the month"), ("onthe", "On the first Monday")],
                              selection: $radio, label: "Monthly repeat")
            }
        }
    }
}

// MARK: Tags

private struct TagsSection: View {
    @State private var active = "work"
    @State private var tags = ["work", "home"]
    private let existing = ["work", "home", "errands", "reading", "health", "garden"]
    var body: some View {
        GallerySection(title: "Tags") {
            Labelled(label: "Label on a row") {
                HStack { KitTagLabel(tag: "work"); KitTagLabel(tag: "home") }
            }
            Labelled(label: "Filter pills (click to filter, again to clear)") {
                HStack(spacing: 6) {
                    ForEach(["work", "home", "errands"], id: \.self) { tag in
                        KitTagFilterPill(tag: tag, active: active == tag) { active = active == tag ? "" : tag }
                    }
                }
            }
            Labelled(label: "Tag picker: click in, type to filter, Return adds, Delete removes the last") {
                KitTagPicker(tags: $tags, suggestions: existing)
            }
            Labelled(label: "Tag picker, empty") {
                KitTagPicker(tags: .constant([]), suggestions: existing)
            }
            Color.clear.frame(height: 120) // room for the drop-down
        }
    }
}

// MARK: Rows

private struct RowsSection: View {
    @Environment(\.theme) private var theme
    private struct Sample: Identifiable { let id: Int; var title: String; var priority: String; var done = false
        var due: String?; var dueTone = 0; var tags: [String] = []; var status = "inbox" }
    @State private var rows = [
        Sample(id: 1, title: "Send the quarterly report", priority: "high", due: "Nov 12", dueTone: 2, tags: ["work"], status: "in-progress"),
        Sample(id: 2, title: "Book the dentist", priority: "medium", due: "Nov 15", dueTone: 1, tags: ["health"], status: "today"),
        Sample(id: 3, title: "Order a new desk lamp", priority: "low", due: "Nov 30", tags: ["home", "errands"]),
        Sample(id: 4, title: "Read the standards draft", priority: "none"),
        Sample(id: 5, title: "Renew the library card", priority: "none", done: true, status: "done"),
    ]
    @State private var selection = RowSelection<Int>()
    @State private var bulk = "complete"

    private let statuses: [(value: String, label: String)] = [
        ("inbox", "Inbox"), ("today", "Today"), ("in-progress", "In Progress"), ("done", "Done"), ("archived", "Archived"),
    ]

    var body: some View {
        GallerySection(title: "Rows, complete circle, priority icon, bulk bar",
                note: "Click selects, ⌘-click adds, ⇧-click selects a run. Right-click a row for its menu. The pencil-style hover controls appear when the pointer is over a row.") {
            Labelled(label: "Complete circle: open, done (hover each)") {
                HStack(spacing: 14) {
                    KitCompleteCircle(done: false) {}
                    KitCompleteCircle(done: true) {}
                    Divider().frame(height: 16)
                    ForEach(["none", "low", "medium", "high"], id: \.self) { p in
                        HStack(spacing: 4) { KitPriorityIcon(priority: p); Text(p).font(.system(size: 11)).foregroundStyle(theme.textMuted) }
                    }
                }
            }
            Labelled(label: "Task rows") {
                KitCard {
                    if !selection.isEmpty && selection.count > 1 {
                        KitBulkBar(count: selection.count,
                                   actions: [("complete", "Mark complete"), ("archive", "Archive"), ("high", "Priority: High"),
                                             ("medium", "Priority: Medium"), ("low", "Priority: Low"), ("none", "Priority: None")],
                                   action: $bulk, onApply: {}, onCancel: { selection.clear() })
                    }
                    ForEach(rows.indices, id: \.self) { i in
                        let row = rows[i]
                        KitRow(isSelected: selection.contains(row.id), onClick: { command, shift in
                            selection.click(row.id, in: rows.map(\.id), command: command, shift: shift)
                        }) { hovering in
                            HStack(spacing: 12) {
                                KitCompleteCircle(done: row.done) { rows[i].done.toggle() }
                                KitPriorityIcon(priority: row.priority)
                                Text(row.title).font(.system(size: 14))
                                    .strikethrough(row.done)
                                    .foregroundStyle(row.done ? theme.textMuted : theme.text200)
                                    .lineLimit(1)
                                Spacer(minLength: 8)
                                if let due = row.due {
                                    Text(due).font(.system(size: 12))
                                        .foregroundStyle(row.dueTone == 2 ? theme.red400 : row.dueTone == 1 ? theme.green400 : theme.textMuted)
                                }
                                ForEach(row.tags.prefix(2), id: \.self) { KitTagLabel(tag: $0) }
                                KitSelect(options: statuses, selection: $rows[i].status, label: "Status", compact: true, tint: statusTint(row.status))
                                KitIconButton(systemImage: "trash", label: "Delete", destructive: true) {}
                                    .opacity(hovering ? 1 : 0)
                            }
                        }
                        .contextMenu {
                            Button(row.done ? "Restore to inbox" : "Mark Complete") { rows[i].done.toggle() }
                            Button("Delete", role: .destructive) {}
                        }
                        if i < rows.count - 1 { KitDivider() }
                    }
                }
            }
        }
    }

    private func statusTint(_ status: String) -> Color {
        switch status {
        case "today": theme.accentText
        case "in-progress": theme.amber400
        case "done": theme.green400
        case "archived": theme.textMuted
        default: theme.text400
        }
    }
}

// MARK: Feedback

private struct FeedbackSection: View {
    @State private var toast = KitToastCenter()
    @State private var confirm = false
    @State private var result = ""
    var body: some View {
        GallerySection(title: "Confirm dialog, toast, tooltip") {
            HStack(spacing: 10) {
                Button("Delete…") { confirm = true }.buttonStyle(KitButtonStyle(.danger))
                Button("Show toast") { toast.show("Task added") }.buttonStyle(KitButtonStyle(.secondary))
                Button("Show error toast") { toast.show("Couldn't reach the server", isError: true) }.buttonStyle(KitButtonStyle(.secondary))
                Text("Hover me for a tooltip").font(.system(size: 13)).kitHelp("Tooltips come from .help()")
                Text(result).font(.system(size: 12))
            }
            .kitConfirm("Delete this task?", isPresented: $confirm, confirmLabel: "Delete", destructive: true) { result = "Deleted" }
            KitToastOverlay(center: toast).frame(height: 56).clipped()
        }
    }
}
#endif

// MARK: Split

#if DEBUG
private struct SplitSection: View {
    @Environment(\.theme) private var theme
    var body: some View {
        GallerySection(title: "Split view", note: "Drag the divider; the width is remembered. Never narrower than 320 on either side.") {
            KitSplitView(storageKey: "gallery", defaultWidth: 360, minLeading: 200, minTrailing: 200) {
                Text("Leading pane").padding(16).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } trailing: {
                Text("Trailing pane").padding(16).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .font(.system(size: 14)).foregroundStyle(theme.text200)
            .frame(height: 120)
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(theme.border1))
        }
    }
}
#endif

// MARK: Sign-in pieces

#if DEBUG
private struct SignInPiecesSection: View {
    @State private var password = ""
    @State private var filled = "correct horse battery"
    @State private var busy = true
    var body: some View {
        GallerySection(title: "Password field, banner, link button, busy and full-width buttons") {
            Labelled(label: "Password field: empty, filled, error") {
                VStack(spacing: 8) {
                    KitSecureField(placeholder: "Password", text: $password)
                    KitSecureField(placeholder: "Password", text: $filled)
                    KitSecureField(placeholder: "Password", text: $filled, isError: true)
                }
            }
            Labelled(label: "Banner: error, notice") {
                VStack(spacing: 8) {
                    KitBanner(kind: .error, text: "Invalid username or password.")
                    KitBanner(kind: .notice, text: "Your password was saved. Sign in with it.")
                }
            }
            Labelled(label: "Link button (hover)") {
                HStack(spacing: 16) {
                    KitLinkButton(title: "Have a setup code?") {}
                    KitLinkButton(title: "Change") {}
                    KitLinkButton(title: "Back to sign in") {}
                }
            }
            Labelled(label: "Full width, busy (spinner, ignores clicks), disabled") {
                VStack(spacing: 8) {
                    Button("Sign in") {}.buttonStyle(KitButtonStyle(.primary, fullWidth: true))
                    Button("Sign in") {}.buttonStyle(KitButtonStyle(.primary, busy: true, fullWidth: true))
                    Button("Continue with single sign-on") {}.buttonStyle(KitButtonStyle(.secondary, busy: true, fullWidth: true))
                    Button("Sign in") {}.buttonStyle(KitButtonStyle(.primary, fullWidth: true)).disabled(true)
                }
                .frame(maxWidth: 384)
            }
        }
    }
}
#endif

// MARK: Dashboard pieces

#if DEBUG
private struct DashboardPiecesSection: View {
    @Environment(\.theme) private var theme
    @State private var done = false
    var body: some View {
        GallerySection(title: "Dashboard card pieces: header styles, badges, muted links, priority dots, tick box, group header") {
            KitCard {
                KitCardHeader(title: "Due Today & Overdue", uppercase: true, badge: "3") {
                    HStack(spacing: 12) {
                        KitLinkButton(title: "Tasks →", size: 12, tone: .muted) {}
                        KitLinkButton(title: "Reminders →", size: 12, tone: .muted) {}
                    }
                }
                KitCardMessage("No events today.")
                KitDivider()
                KitCardMessage(text: "No tasks set to \"Today\" status.") { KitLinkButton(title: "Set some focus tasks →") {} }
                KitDivider()
                KitGroupHeaderRow(text: "Morning")
                HStack(spacing: 12) {
                    KitCompleteSquare(done: done) { done.toggle() }
                    KitCompleteSquare(done: true) {}
                    KitCompleteSquare(done: false, enabled: false) {}
                    Divider().frame(height: 16)
                    ForEach(["none", "low", "medium", "high"], id: \.self) { p in
                        HStack(spacing: 4) { KitPriorityDot(priority: p); Text(p).font(.system(size: 11)).foregroundStyle(theme.textMuted) }
                    }
                    Divider().frame(height: 16)
                    KitCompleteCircle(done: false, tint: theme.accentHover) {}
                    KitCompleteCircle(done: false, tint: theme.red500) {}
                }
                .padding(16)
            }
            HStack(spacing: 12) {
                KitBadge(text: "3")
                KitBadge(text: "4", tone: .warn)
                Button {} label: { KitBadge(text: "2 tasks slipping", tone: .warn, outlined: true) }.buttonStyle(.plain)
            }
        }
    }
}
#endif

// MARK: Capture pieces

#if DEBUG
private struct CapturePiecesSection: View {
    @State private var type = "task"
    var body: some View {
        GallerySection(title: "Pill selector, neutral banner, info badge") {
            Labelled(label: "Pill selector (wraps): click one") {
                KitPillSelector(options: CaptureTypes.all.map { (value: $0, label: CaptureTypes.label($0)) }, selection: $type, label: "Type")
                    .frame(maxWidth: 420, alignment: .leading)
            }
            Labelled(label: "Banner: neutral") {
                KitBanner(kind: .neutral, text: "AI isn't set up on this server, so Capture saves what you type as a note.")
            }
            Labelled(label: "Badges: low confidence, medium confidence") {
                HStack(spacing: 8) {
                    KitBadge(text: "Low confidence — check fields", tone: .warn)
                    KitBadge(text: "Medium confidence", tone: .info)
                }
            }
        }
    }
}
#endif

// MARK: Notes pieces

#if DEBUG
private struct NotesPiecesSection: View {
    @Environment(\.theme) private var theme
    @State private var text = "# A heading\n\nSelect some of this text and use the toolbar, or ⌘B and ⌘I.\n\n- a list\n- [ ] a checklist"
    @State private var controller = KitMarkdownEditorController()
    @State private var selected = "n2"
    @State private var expanded = true
    var body: some View {
        GallerySection(title: "Markdown editor with its toolbar, tree rows",
                       note: "The editor is a real text view: spelling, undo and the system's text services. The toolbar uses the shared MarkdownFormat rules.") {
            Labelled(label: "Format toolbar and writing area") {
                VStack(spacing: 6) {
                    KitFormatToolbar(controller: controller)
                    KitMarkdownEditor(text: $text, controller: controller)
                        .frame(height: 170)
                        .background(theme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(theme.border2))
                }
            }
            Labelled(label: "Tree rows: folder (open, with hover buttons), subfolder, notes (selected, pinned, locked), drop target") {
                VStack(spacing: 1) {
                    KitTreeRow(title: "Work", kind: .folder(expanded: expanded, hasChildren: true), onToggle: { expanded.toggle() }) { hovering in
                        HStack(spacing: 2) {
                            KitIconButton(systemImage: "plus", label: "New subfolder") {}
                            KitIconButton(systemImage: "pencil", label: "Rename") {}
                            KitIconButton(systemImage: "xmark", label: "Delete folder", destructive: true) {}
                        }.opacity(hovering ? 1 : 0)
                    }
                    if expanded {
                        KitTreeRow(title: "Plans", kind: .folder(expanded: false, hasChildren: true), depth: 1)
                        KitTreeRow(title: "Budget 2027", kind: .note, depth: 1, selected: selected == "n1", onClick: { selected = "n1" })
                        KitTreeRow(title: "Quarterly goals", kind: .note, depth: 1, selected: selected == "n2", pinned: true, onClick: { selected = "n2" })
                        KitTreeRow(title: "Salary notes", kind: .note, depth: 1, locked: true)
                    }
                    KitTreeRow(title: "Home (a note is being dropped here)", kind: .folder(expanded: true, hasChildren: false), dropTargeted: true)
                }
                .frame(maxWidth: 320)
            }
        }
    }
}

// MARK: Handwriting and attachments

private struct HandwritingAttachmentsSection: View {
    @Environment(\.theme) private var theme
    @State private var color = DrawingRenderer.colors[1]
    @State private var width: Double = 3
    @State private var erasing = false
    @State private var doc = DrawingDoc(w: 0, h: 300, strokes: [])
    @State private var controller = KitDrawingController()
    @State private var dropping = true
    @State private var dropOff = false

    private var matchTheme: DrawingPaper { DrawingPaper.resolve("theme", theme: theme) }

    var body: some View {
        GallerySection(title: "Handwriting: pen colours, drawing toolbar, canvas; attachments: thumbnails, file rows, drop area",
                       note: "The paper follows the theme (Settings ▸ Notes ▸ Handwriting paper can force Dark or White) and the pen colours show the shade they draw in on it. The canvas is live: draw with the mouse, trackpad or a pen.") {
            Labelled(label: "Pen colours on the three papers (follows theme, Dark, White)") {
                HStack(spacing: 18) {
                    ForEach([("Theme", matchTheme), ("Dark", DrawingPaper.dark), ("White", DrawingPaper.white)], id: \.0) { name, paper in
                        KitPenSwatches(color: $color, erasing: false, paper: paper)
                            .padding(8).background(Color(cgColor: paper.ground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .help(name)
                    }
                }
            }
            Labelled(label: "Drawing toolbar and canvas (live)") {
                VStack(spacing: 8) {
                    KitDrawingToolbar(color: $color, width: $width, erasing: $erasing, paper: matchTheme, canUndo: !doc.strokes.isEmpty,
                                      undo: { controller.undo() }, clear: { doc.strokes = [] })
                    KitDrawingCanvas(doc: $doc, color: color, width: width, erasing: erasing, paper: matchTheme, controller: controller)
                        .frame(height: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(theme.border2))
                }
            }
            Labelled(label: "Attachment thumbnail (a picture that can't load), file rows (PDF, text)") {
                HStack(alignment: .top, spacing: 12) {
                    KitAttachmentThumb(path: "/none.png", name: "whiteboard.png") {}
                    VStack(alignment: .leading, spacing: 2) {
                        KitAttachmentFileRow(name: "budget-2027.pdf", mimeType: "application/pdf") {}
                        KitAttachmentFileRow(name: "meeting-minutes.txt", mimeType: "text/plain") {}
                    }.frame(maxWidth: 260)
                }
            }
            Labelled(label: "Drop area while files are dragged over (and not)") {
                HStack(spacing: 12) {
                    Text("A note's writing area").font(.system(size: 13)).foregroundStyle(theme.textMuted)
                        .frame(width: 240, height: 90).background(theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .kitFileDrop(isTargeted: $dropping) { _ in }
                    Text("Not targeted").font(.system(size: 13)).foregroundStyle(theme.textMuted)
                        .frame(width: 240, height: 90).background(theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .kitFileDrop(isTargeted: $dropOff) { _ in }
                }
            }
        }
    }
}

// MARK: Charts

private struct ChartsSection: View {
    private let weeks: [[KitHeatCell]] = (0..<12).map { w in
        (0..<7).map { d in
            let n = w * 7 + d
            if w == 11 && d > 3 { return KitHeatCell(kind: .future, tooltip: "") }
            if d == 6 { return KitHeatCell(kind: .notScheduled, tooltip: "Sun —") }
            return n % 3 == 0 ? KitHeatCell(kind: .missed, tooltip: "Day \(n)") : KitHeatCell(kind: .done, tooltip: "Day \(n) ✓")
        }
    }
    private let bars: [KitBar] = [(0.9, KitBar.Tone.good), (0.7, .fair), (0.4, .low), (0, .none), (1, .good), (0.55, .fair), (0.2, .low), (0.85, .good),
                                  (0.6, .fair), (0.3, .low), (0.95, .good), (0.5, .fair)].map { KitBar(fraction: $0.0, tone: $0.1, tooltip: "\(Int($0.0 * 100))%") }

    var body: some View {
        GallerySection(title: "Heatmap and bar chart",
                       note: "The routine page's 12-week grid and weekly completion bars. They take plain values, so Analytics can use them too. Hover a square or a bar for its tooltip.") {
            Labelled(label: "Heatmap: done, missed, not scheduled (Sundays), future") {
                KitHeatmap(weeks: weeks, leadingCaption: "Aug 24", summary: "Last 12 weeks: 44 of 70 scheduled days done")
                    .frame(maxWidth: 320, alignment: .leading)
            }
            Labelled(label: "Bar chart: good (80% and up), fair (50% and up), low, none") {
                KitBarChart(bars: bars, leadingCaption: "Aug 24", summary: "Weekly completion rate over 12 weeks")
                    .frame(maxWidth: 320)
            }
        }
    }
}


// MARK: Reorderable rows

private struct ReorderSection: View {
    @Environment(\.theme) private var theme
    @State private var items = [(id: 1, text: "Milk"), (id: 2, text: "Eggs"), (id: 3, text: "Bread"), (id: 4, text: "Jam")]
    @State private var targeted: Int?

    var body: some View {
        GallerySection(title: "Drag handle and drop line (reorderable rows)",
                       note: "Drag a grip onto another row; the accent line shows where it lands. The Lists screen also moves the selected row with ⌥↑ and ⌥↓.") {
            HStack(spacing: 8) { KitAvatar(name: "Sam Lee"); KitAvatar(name: "Alex") }
            KitCard {
                ForEach(items, id: \.id) { item in
                    HStack(spacing: 10) {
                        KitDragHandle(id: item.id)
                        Text(item.text).font(.system(size: 14)).foregroundStyle(theme.text200)
                        Spacer()
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .kitReorderTarget(isTargeted: Binding(get: { targeted == item.id }, set: { targeted = $0 ? item.id : nil })) { dragged in
                        guard let from = items.firstIndex(where: { $0.id == dragged }), let to = items.firstIndex(where: { $0.id == item.id }), from != to else { return false }
                        items.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
                        return true
                    }
                    if item.id != items.last?.id { KitDivider() }
                }
            }
        }
    }
}


// MARK: Table

private struct TableSection: View {
    @Environment(\.theme) private var theme
    @State private var sortedBy = "added"
    @State private var ascending = false
    private let columns = [KitTableColumn(id: "title", label: "Title"), KitTableColumn(id: "site", label: "Site", width: 130),
                           KitTableColumn(id: "added", label: "Added", width: 90)]
    private let rows = [("Swift documentation", "swift.org", "Nov 12"), ("React docs", "react.dev", "Nov 3"), ("A page with no icon", "example.test", "Oct 28")]

    var body: some View {
        GallerySection(title: "Table: sortable column headings, site icon, delete-only bulk bar",
                       note: "Click a heading to sort by it; click it again to reverse. The Bookmarks screen uses this.") {
            KitCard {
                KitTableHeader(columns: columns, sortedBy: sortedBy, ascending: ascending) { id in
                    if sortedBy == id { ascending.toggle() } else { sortedBy = id; ascending = id != "added" }
                }
                ForEach(rows, id: \.0) { row in
                    HStack(spacing: 12) {
                        HStack(spacing: 8) {
                            KitSiteIcon(host: row.1)
                            Text(row.0).font(.system(size: 14, weight: .medium)).foregroundStyle(theme.text100).lineLimit(1)
                        }
                        .kitTableCell(columns[0])
                        Text(row.1).font(.system(size: 13)).foregroundStyle(theme.accentText).kitTableCell(columns[1])
                        Text(row.2).font(.system(size: 13)).foregroundStyle(theme.textMuted).kitTableCell(columns[2])
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    KitDivider()
                }
            }
            KitCard { KitBulkDeleteBar(count: 3, onDelete: {}, onCancel: {}) }
        }
    }
}


// MARK: Calendar

private struct CalendarSection: View {
    @State private var date = Date()
    @State private var time = Date()
    @State private var week = true

    private var days: [KitCalendarDay] {
        let names = ["2026-11-09", "2026-11-10", "2026-11-11", "2026-11-12", "2026-11-13", "2026-11-14", "2026-11-15"]
        return names.enumerated().map { i, d in
            KitCalendarDay(id: d, number: 9 + i, isToday: i == 6, inMonth: true,
                           chips: i == 0 ? [KitCalendarChip(id: 1, title: "Team sync", time: "9:30 AM", color: "#6366f1")]
                                  : i == 2 ? [KitCalendarChip(id: 2, title: "Launch day", time: nil, color: "#f59e0b"), KitCalendarChip(id: 3, title: "Lunch with Sam", time: "12:30 PM", color: "#10b981")] : [],
                           longName: "Day \(9 + i)")
        }
    }

    var body: some View {
        GallerySection(title: "Calendar: week and month grid, event chips, colour dot, date and time fields, amber notice",
                       note: "Click a day's number to start an event there; double-click an empty part of a day does the same. The selected chip has an accent ring.") {
            KitPillSelector(options: [(true, "Week"), (false, "Month")], selection: $week, label: "View")
            KitCalendarGrid(isMonth: !week, weeks: week ? [days] : [days, days.map { var d = $0; d = KitCalendarDay(id: d.id + "b", number: d.number + 7, isToday: false, inMonth: d.number < 14, chips: d.chips, longName: d.longName); return d }],
                            selectedEvent: 3, onEvent: { _ in }, onOpenEvent: { _ in }, onDay: { _ in },
                            eventMenu: { _ in Button("Edit…") {} }, dayMenu: { _ in Button("New Event on This Day") {} })
            HStack(spacing: 16) {
                HStack(spacing: 6) { KitColorDot(hex: "#6366f1"); Text("Work") }
                HStack(spacing: 6) { KitColorDot(hex: "#ec4899"); Text("Family") }
                KitDateField(value: $date, label: "Date")
                KitTimeField(value: $time, label: "Time")
            }
            KitBanner(kind: .warn, text: "No calendars connected. Events created here are stored locally only.")
        }
    }
}

// MARK: Analytics

private struct AnalyticsSection: View {
    @Environment(\.theme) private var theme

    var body: some View {
        GallerySection(title: "Analytics: stat tiles, rate bar, column and line charts, shade heatmap",
                       note: "Hover a column or a point for its numbers. Charts are Swift Charts; colours come from the theme.") {
            HStack(alignment: .top, spacing: 10) {
                KitStatTile(title: "True on-time rate", value: "78%", note: "within 30 min of due time · 41 items with due dates", valueColor: theme.green400, hero: true)
                KitStatTile(title: "Completed", value: "64", note: "Last 30 days")
                KitStatTile(title: "Best day", value: "Tuesday", note: "14 completions", compact: true)
            }
            HStack(spacing: 14) {
                KitRateBar(rate: 85).frame(width: 140)
                KitRateBar(rate: 58).frame(width: 140)
                KitRateBar(rate: 30).frame(width: 140)
            }
            KitChartLegend(items: [("Early", theme.green500), ("On time", theme.accent), ("Same-day late", theme.yellow400), ("Late 8+d", theme.red500)])
            KitColumnChart(columns: (0..<8).map { i in
                KitColumn(label: "Sep \(i + 1)", parts: [KitColumnPart(name: "Early", value: 1 + i % 3, color: theme.green500),
                                                     KitColumnPart(name: "On time", value: 2 + i % 4, color: theme.accent),
                                                     KitColumnPart(name: "Same-day late", value: i % 2, color: theme.yellow400),
                                                     KitColumnPart(name: "Late 8+d", value: i == 3 ? 2 : 0, color: theme.red500)],
                          title: "Week of Sep \(i + 1)")
            }, height: 140, summary: "Sample stacked columns")
            KitLineChart(points: (0..<10).map { i in KitLinePoint(label: "Sep \(i + 1)", value: i == 4 ? nil : 50 + (i * 11) % 45, detail: "sample") },
                         color: theme.green500, percent: true, height: 130, summary: "Sample line")
            KitShadeHeatmap(weeks: (0..<12).map { w in (0..<7).map { d in KitShadeCell(intensity: (w * 3 + d * 5) % 7 > 3 ? (w + d) % 5 : 0, isFuture: w == 11 && d > 3, tooltip: "Day") } },
                            dayLabels: ["M", "T", "W", "T", "F", "S", "S"], weekLabels: (0..<12).map { "Sep \($0 * 7 % 28 + 1)" }, summary: "Sample heatmap")
        }
    }
}

// MARK: AI Chat

private struct ChatSection: View {
    @State private var text = ""
    @State private var focus = false

    var body: some View {
        GallerySection(title: "AI Chat: message bubbles, typing dots, message box",
                       note: "Return sends, ⇧Return starts a new line, ⌘Return sends too. Hover a bubble for Copy; right-click also copies.") {
            VStack(spacing: 14) {
                KitChatBubble(text: "What tasks are slipping this week?", isUser: true, remaining: nil) {}
                KitChatBubble(text: "Three tasks are overdue:\n• Send the quarterly report\n• Renew the domain\n• Book the dentist", isUser: false, remaining: "41 messages remaining today") {}
                KitTypingDots()
                KitChatInput(placeholder: "Ask anything…", text: $text, focusRequest: $focus, canSend: !text.isEmpty, onSend: {})
            }
            .frame(maxWidth: 560)
        }
    }
}

// MARK: Search

private struct SearchSection: View {
    @State private var text = "trip"

    var body: some View {
        GallerySection(title: "Search: palette field, result rows with highlighted words, key caps",
                       note: "The real palette sits over a dimmed window (KitPalette); ↑↓ move the highlight, Return opens, Esc closes.") {
            VStack(spacing: 0) {
                KitPaletteField(placeholder: "Search notes, tasks, lists, bookmarks…", text: $text, onMove: { _ in }, onSubmit: {}, onEscape: {})
                KitGroupLabel(text: "Notes").padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 4)
                KitSearchRow(icon: "doc.text", title: SearchStore.pieces(of: "Trip plan: Lisbon in March", matching: text), subtitle: "travel, planning", isHighlighted: true, onOpen: {})
                    .padding(.horizontal, 12)
                KitSearchRow(icon: "checkmark.circle", title: SearchStore.pieces(of: "Book the trip flights", matching: text), subtitle: "due 2026-12-01", isHighlighted: false, onOpen: {})
                    .padding(.horizontal, 12)
                HStack(spacing: 8) { KitKeyCap(text: "↑↓"); KitKeyCap(text: "↵"); KitKeyCap(text: "Esc") }.padding(14)
            }
            .frame(maxWidth: 576)
            .background(Color.clear)
        }
    }
}

// MARK: Help

private struct HelpSection: View {
    var body: some View {
        GallerySection(title: "Help: contents list, shortcut table",
                       note: "The help text itself is drawn by KitHelpPage (a web view in the theme's colours); the contents list marks the section in view. ⌘? opens the Help window, ? opens the shortcuts on their own.") {
            HStack(alignment: .top, spacing: 24) {
                KitContentsList(sections: [("capture", "Capture"), ("today", "Today"), ("tasks", "Tasks"), ("notes", "Notes")], current: "tasks", onSelect: { _ in })
                    .frame(width: 190, height: 170)
                KitShortcutTable(rows: Array(MacShortcuts.groups[0].rows.prefix(6)))
            }
        }
    }
}

// MARK: Settings

private struct SettingsSection: View {
    @Environment(\.theme) private var theme
    @State private var items = [KitSortItem(id: "today", title: "Today", isOn: true, isFixed: true), KitSortItem(id: "tasks", title: "Tasks", isOn: true),
                                KitSortItem(id: "notes", title: "Notes", detail: "Folders beside the open note", isOn: true), KitSortItem(id: "lists", title: "Lists", isOn: false)]
    @State private var selected = "midnight"
    @State private var accent = "#10b981"
    @State private var radio = "12h"
    @State private var dot = "#6366f1"
    @State private var disclosureOpen = true

    var body: some View {
        GallerySection(title: "Settings: setting row, sort list, theme cards, colour field, file button",
                       note: "Drag a grip (or ⌥↑ ⌥↓ on a focused row) to reorder; the first and last rows can be fixed. The Settings window's tab bar is the system's.") {
            KitSettingRow(title: "Time Format", detail: "How times are written everywhere") {
                KitRadioGroup(options: [("12h", "12-hour (1:30 PM)"), ("24h", "24-hour (13:30)")], selection: $radio, label: "Time format", horizontal: true)
            }
            KitSortList(items: items, onMove: { id, offset in
                guard let from = items.firstIndex(where: { $0.id == id }) else { return }
                let to = min(max(from + offset, 1), items.count - 1)
                items.insert(items.remove(at: from), at: to)
            }, onToggle: { id in if let i = items.firstIndex(where: { $0.id == id }) { items[i].isOn.toggle() } })
            HStack(spacing: 10) {
                ForEach(["dark", "midnight", "light"], id: \.self) { id in
                    KitThemeCard(name: Theme.labels[id]?.label ?? id, detail: Theme.labels[id]?.desc ?? "", preview: Theme.builtIn.first { $0.id == id } ?? .darkDefault,
                                 isSelected: selected == id) { selected = id }
                }
            }
            HStack(spacing: 20) {
                KitColorField(hex: $accent, label: "Accent colour")
                KitFileButton(title: "Import…", systemImage: "square.and.arrow.down", types: [.json]) { _ in }
            }
            HStack(alignment: .top, spacing: 30) {
                HStack(spacing: 10) {
                    KitColorSwatch(hex: $dot, label: "Calendar colour")
                    Text("Colour dot: click it to change the colour").font(.system(size: 12)).foregroundStyle(theme.textMuted)
                }
                KitDisclosure(title: "Calendars to sync (2/3)", isOpen: $disclosureOpen) {
                    KitCheckbox(title: "Work", isOn: .constant(true))
                    KitCheckbox(title: "Home", isOn: .constant(true))
                    KitCheckbox(title: "Birthdays", isOn: .constant(false))
                }
            }
        }
    }
}
#endif
