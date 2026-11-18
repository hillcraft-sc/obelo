import SwiftUI

// Calendar — the web's week view as a phone agenda: a Monday-first week, each day a card of
// its events, with previous/next/today navigation. Read-only for now (create/edit on the web).

struct CalendarView: View {
    @Environment(AppState.self) private var app
    @Environment(\.theme) private var theme

    struct Response: Decodable { let from: String; let days: Int; let today: String; let events: [CalendarEvent]; let sources: [CalendarSourceInfo]? }

    @State private var weekStart: String?
    @State private var data: Response?
    @State private var error: String?
    @State private var newEventDate: NewEventDay?

    struct NewEventDay: Identifiable { let day: String; var id: String { day } }

    private var userTZ: TimeZone { TimeZone(identifier: app.me?.user.timezone ?? "") ?? .current }

    var body: some View {
        Page(maxWidth: 1024, refresh: load) {
            // The heading is the week shown, as on the web (views/calendar/index.ejs)
            PageHeader(title: rangeLabel) {
                PrimaryButton(title: "New event", systemImage: "plus") { newEventDate = NewEventDay(day: data?.today ?? Fmt.ymd(.now, in: userTZ)) }
            }
            HStack {
                Spacer()
                HStack(spacing: 4) {
                    navButton("chevron.left") { shift(-7) }
                    SecondaryButton(title: "Today") { weekStart = Self.monday(of: Fmt.ymd(.now, in: userTZ)) }
                    navButton("chevron.right") { shift(7) }
                }
            }
            if let error { Banner(kind: .error, text: error) }
            // Same notice as the web, only when the server says nothing is connected (needs server 3.52.0)
            if let sources = data?.sources, sources.isEmpty {
                Banner(kind: .warning, text: "No calendars connected. Events created here are stored locally only.")
            }
            if let data, let start = weekStart {
                ForEach(0..<7, id: \.self) { offset in
                    let day = Self.addDays(start, offset)
                    dayCard(day, events: data.events.filter { $0.day == day }, isToday: day == data.today)
                }
                if let sources = data.sources, !sources.isEmpty { legend(sources) }
            } else {
                ProgressView().frame(maxWidth: .infinity).padding(40)
            }
        }
        .onNewItem("calendar") { newEventDate = NewEventDay(day: data?.today ?? Fmt.ymd(.now, in: userTZ)) }
        .sheet(item: $newEventDate) { new in
            EventForm(event: nil, defaultDate: new.day) { _ in app.dataChanged() }
        }
        #if DEBUG
        .onAppear { if UserDefaults.standard.bool(forKey: "newEvent") { newEventDate = NewEventDay(day: Fmt.ymd(.now, in: userTZ)) } }
        #endif
        .task(id: "\(weekStart ?? "")|\(app.dataVersion)") {
            if weekStart == nil { weekStart = Self.monday(of: Fmt.ymd(.now, in: userTZ)); return }
            await load()
        }
    }

    /// The connected calendars, as the web's legend under the grid: a dot, the name, "· synced 3:05 PM"
    private func legend(_ sources: [CalendarSourceInfo]) -> some View {
        FlowLayout(spacing: 14) {
            ForEach(sources) { src in
                HStack(spacing: 6) {
                    Circle().fill(Color(hex: src.color)).frame(width: 10, height: 10)
                    Text(src.name).font(.system(size: 12)).foregroundStyle(theme.textMuted)
                    if let synced = src.lastSynced {
                        Text("· synced \(Fmt.clock(synced, hour12: app.hour12, tz: userTZ))").font(.system(size: 12)).foregroundStyle(theme.textMuted.opacity(0.7))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func navButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.text400)
                .frame(width: 34, height: 34)
                .background(theme.elevated, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.border2, lineWidth: 1))
        }
        .buttonStyle(PressableStyle())
    }

    private func dayCard(_ day: String, events: [CalendarEvent], isToday: Bool) -> some View {
        Card {
            HStack {
                Text(Fmt.weekdayShort(day)).font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isToday ? theme.accentText : theme.text300)
                if isToday { Badge(text: "Today", fg: theme.onAccent, bg: theme.accent) }
                Spacer()
                Button { newEventDate = NewEventDay(day: day) } label: {
                    Image(systemName: "plus").font(.system(size: 12, weight: .semibold)).foregroundStyle(theme.textMuted)
                        .frame(width: 28, height: 24).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("New event on \(Fmt.weekdayShort(day))")
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(isToday ? theme.accent.opacity(0.1) : .clear)
            if events.isEmpty {
                RowDivider()
                Text("No events").font(.system(size: 13)).italic().foregroundStyle(theme.textMuted)
                    .padding(.horizontal, 16).padding(.vertical, 10)
            }
            ForEach(events.sorted { ($0.allDay ? 0 : 1, $0.startAt) < ($1.allDay ? 0 : 1, $1.startAt) }) { ev in
                RowDivider()
                NavigationLink(value: Route.event(ev)) {
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 2).fill(Color(hex: ev.color)).frame(width: 3, height: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ev.title).font(.system(size: 14, weight: .medium)).foregroundStyle(theme.text200).lineLimit(1)
                            Text(timeText(ev)).font(.system(size: 12)).foregroundStyle(theme.textMuted).lineLimit(1)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func timeText(_ ev: CalendarEvent) -> String {
        var parts = [ev.allDay ? "All day" : "\(Fmt.clock(ev.startAt, hour12: app.hour12, tz: userTZ)) – \(Fmt.clock(ev.endAt, hour12: app.hour12, tz: userTZ))"]
        if let loc = ev.location, !loc.isEmpty { parts.append(loc) }
        return parts.joined(separator: " · ")
    }

    private var rangeLabel: String {
        guard let s = weekStart else { return "" }
        return "\(Fmt.shortDay(s)) – \(Fmt.shortDay(Self.addDays(s, 6)))"
    }

    private func shift(_ days: Int) {
        if let s = weekStart { weekStart = Self.addDays(s, days) }
    }

    private func load() async {
        guard let weekStart else { return }
        do {
            data = try await APIClient.shared.get("/calendar", query: ["from": weekStart, "days": "7"])
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    static func addDays(_ ymd: String, _ n: Int) -> String {
        guard let d = Fmt.day(ymd) else { return ymd }
        return Fmt.ymd(d.addingTimeInterval(Double(n) * 86400), in: TimeZone(identifier: "UTC")!)
    }

    /// Weeks start on Monday, like the web calendar
    static func monday(of ymd: String) -> String {
        guard let d = Fmt.day(ymd) else { return ymd }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let weekday = cal.component(.weekday, from: d) // 1 = Sunday
        return addDays(ymd, -((weekday + 5) % 7))
    }
}

struct EventDetailView: View {
    @Environment(AppState.self) private var app
    @Environment(Toast.self) private var toast
    @Environment(\.theme) private var theme
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @State var event: CalendarEvent
    @State private var editing = false
    @State private var confirmDelete = false

    private var tz: TimeZone { TimeZone(identifier: app.me?.user.timezone ?? "") ?? .current }

    var body: some View {
        Page {
            Card(padding: 20) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 8) {
                        Dot(color: Color(hex: event.color), size: 10)
                        Text(event.calendarName ?? "Calendar").font(.system(size: 12)).foregroundStyle(theme.textMuted)
                    }
                    Text(event.title).font(.system(size: 24, weight: .bold)).foregroundStyle(theme.textPrimary)
                    Label(Fmt.longDay(event.day), systemImage: "calendar").foregroundStyle(theme.text300)
                    Label(event.allDay ? "All day" : "\(Fmt.clock(event.startAt, hour12: app.hour12, tz: tz)) – \(Fmt.clock(event.endAt, hour12: app.hour12, tz: tz))",
                          systemImage: "clock").foregroundStyle(theme.text300)
                    if let loc = event.location, !loc.isEmpty {
                        Label(loc, systemImage: "mappin.and.ellipse").foregroundStyle(theme.text300)
                    }
                    if let link = event.url, let url = URL(string: link) {
                        Button { openURL(url) } label: { Label(link, systemImage: "link").lineLimit(1) }
                            .foregroundStyle(theme.accentText)
                    }
                    if let desc = event.description, !desc.isEmpty {
                        RowDivider()
                        Text(desc).font(.system(size: 14)).foregroundStyle(theme.text400).textSelection(.enabled)
                    }
                }
                .font(.system(size: 14))
            }
            if !event.editable {
                Text(event.deletable ? "Synced from \(event.calendarName ?? "another calendar"), so it's edited there. Deleting it here only removes Obelo's copy until the next sync."
                                     : "This event is on a calendar shared with you.")
                    .font(.system(size: 12)).foregroundStyle(theme.textMuted).padding(.horizontal, 4)
            }
            if event.deletable {
                HStack {
                    Spacer()
                    SecondaryButton(title: "Delete", systemImage: "trash", tint: theme.red400) { confirmDelete = true }
                }
            }
        }
        .themedNavBar(theme, title: "Calendar")
        .toolbar {
            if event.editable {
                ToolbarItem(placement: .primaryAction) { Button("Edit") { editing = true } }
            }
        }
        .sheet(isPresented: $editing) {
            EventForm(event: event, defaultDate: event.day) { updated in
                if let updated { event = updated }
                app.dataChanged()
            }
        }
        .confirmationDialog("Delete this event?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                toast.run {
                    try await APIClient.shared.delete("/calendar/events/\(event.id)")
                    toast.show("Event deleted")
                    app.dataChanged()
                    dismiss()
                }
            }
        }
    }
}

/// Opens an event by id (from search, or links that only carry the id)
struct EventLoader: View {
    @Environment(\.theme) private var theme
    let id: Int
    @State private var event: CalendarEvent?
    @State private var error: String?

    var body: some View {
        Loadable(value: event, error: error, retry: load) { EventDetailView(event: $0) }
            .themedNavBar(theme, title: "Calendar")
            .task { await load() }
    }

    private func load() async {
        struct R: Decodable { let event: CalendarEvent }
        do { event = (try await APIClient.shared.get("/calendar/events/\(id)") as R).event }
        catch { self.error = error.localizedDescription }
    }
}

/// calendar/new.ejs and edit.ejs. The calendar can only be chosen when creating, as on the web.
struct EventForm: View {
    @Environment(\.theme) private var theme
    let event: CalendarEvent?
    let defaultDate: String
    let saved: (CalendarEvent?) -> Void

    struct Choice: Decodable, Hashable { let value: String; let label: String; let color: String }
    struct Calendars: Decodable { let calendars: [Choice]; let defaultTarget: String }

    @State private var title = ""
    @State private var date: String? = nil
    @State private var allDay = false
    @State private var startTime: String? = "09:00"
    @State private var endTime: String? = "10:00"
    @State private var location = ""
    @State private var notes = ""
    @State private var target = "local"
    @State private var choices: [Choice] = []
    @State private var error: String?
    @State private var loaded = false

    var body: some View {
        FormSheet(title: event == nil ? "New Event" : "Edit Event", saveTitle: event == nil ? "Create" : "Save",
                  canSave: !title.trimmingCharacters(in: .whitespaces).isEmpty, error: error, save: save) {
            FormSection(label: "Title") { ThemedField(placeholder: "Event title", text: $title) }
            FormSection(label: "Date") { OptionalDateField(ymd: $date, allowClear: false) }
            ToggleRow(title: "All day", isOn: $allDay)
            if !allDay {
                HStack(spacing: 12) {
                    FormSection(label: "Start time") { OptionalTimeField(hhmm: $startTime, allowClear: false) }
                    FormSection(label: "End time") { OptionalTimeField(hhmm: $endTime, allowClear: false) }
                }
                .onChange(of: startTime) { old, new in
                    // Keep the length when the start moves, like most calendar apps
                    guard let o = minutes(old), let n = minutes(new), let e = minutes(endTime) else { return }
                    endTime = hhmm(min(e + (n - o), 23 * 60 + 59))
                }
            }
            FormSection(label: "Location") { ThemedField(placeholder: "Optional", text: $location) }
            FormSection(label: "Notes") { ThemedField(placeholder: "Optional", text: $notes, axis: .vertical).lineLimit(3...8) }
            if event == nil {
                FormSection(label: "Calendar") {
                    if choices.isEmpty { ProgressView() } else {
                        SelectField(options: choices.map { ($0.value, $0.label) }, selection: $target)
                    }
                }
            }
        }
        .task {
            guard !loaded else { return }
            loaded = true
            if let e = event {
                title = e.title; date = e.day; allDay = e.allDay
                startTime = e.startTime ?? "09:00"; endTime = e.endTime ?? "10:00"
                location = e.location ?? ""; notes = e.description ?? ""
            } else {
                date = defaultDate
                if let r: Calendars = try? await APIClient.shared.get("/calendar/calendars") {
                    choices = r.calendars
                    target = r.calendars.contains { $0.value == r.defaultTarget } ? r.defaultTarget : (r.calendars.first?.value ?? "local")
                }
            }
        }
    }

    private func minutes(_ hhmm: String?) -> Int? {
        let p = (hhmm ?? "").split(separator: ":").compactMap { Int($0) }
        return p.count == 2 ? p[0] * 60 + p[1] : nil
    }
    private func hhmm(_ m: Int) -> String { String(format: "%02d:%02d", m / 60, m % 60) }

    private func save() async -> Bool {
        var body: [String: Any] = [
            "title": title, "date": date ?? defaultDate, "allDay": allDay,
            "location": location, "description": notes,
        ]
        if !allDay { body["startTime"] = startTime ?? "09:00"; body["endTime"] = endTime ?? "10:00" }
        do {
            if let e = event {
                struct R: Decodable { let event: CalendarEvent }
                let r: R = try await APIClient.shared.post("/calendar/events/\(e.id)", body, method: "PUT")
                saved(r.event)
            } else {
                body["calendarTarget"] = target
                try await APIClient.shared.post("/calendar/events", body)
                saved(nil)
            }
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }
}
