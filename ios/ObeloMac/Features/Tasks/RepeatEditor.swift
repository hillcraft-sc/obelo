import SwiftUI

/// "Repeat" with the ten fixed choices and the Custom panel (every N days, weeks, months or years; for
/// months, on a day or on "the first Monday"). The rule string is the one the web form writes.
struct RepeatEditor: View {
    @Environment(\.theme) private var theme
    @Binding var recurring: Bool
    @Binding var rule: String

    private var parsed: RecurrenceRule { RecurrenceRule(rule) }

    private var choices: [(value: String, label: String)] {
        Fmt.recurRules.map { (value: $0.0, label: $0.1) } + [(value: "custom", label: "Custom…")]
    }

    private func edit(_ change: (inout RecurrenceRule) -> Void) {
        var r = parsed
        change(&r)
        rule = r.raw
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                KitCheckbox(title: "Repeat", isOn: $recurring)
                if recurring {
                    KitSelect(options: choices,
                              selection: Binding(get: { parsed.isCustom ? "custom" : rule },
                                                 set: { rule = $0 == "custom" ? RecurrenceRule(custom: .daily).raw : $0 }),
                              label: "Repeat rule")
                        .frame(maxWidth: 220)
                }
                Spacer(minLength: 0)
            }
            if recurring, parsed.isCustom { customPanel }
        }
    }

    private var customPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("Every").font(.system(size: 14)).foregroundStyle(theme.text300)
                KitNumberField(value: Binding(get: { parsed.every }, set: { n in edit { $0.every = max(1, min(99, n)) } }),
                               range: 1...99, label: "Repeat every")
                KitSelect(options: RecurrenceRule.Frequency.allCases.map { (value: $0, label: $0.unit) },
                          selection: Binding(get: { parsed.frequency }, set: { f in edit { $0.frequency = f } }),
                          label: "Repeat unit")
                    .frame(width: 120)
            }
            if parsed.frequency == .monthly { monthly }
        }
        .padding(12)
        .background(theme.elevated.opacity(0.5), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(theme.border1))
    }

    private enum Mode: Hashable { case each, onThe }

    private var mode: Mode { if case .onThe = parsed.monthMode { .onThe } else { .each } }

    @ViewBuilder private var monthly: some View {
        KitRadioGroup(options: [(value: Mode.each, label: "Each day of the month"), (value: Mode.onThe, label: "On the …")],
                      selection: Binding(get: { mode }, set: { m in
                          edit { $0.monthMode = m == .each ? .each(day: 1) : .onThe(ordinal: "first", weekday: "monday") }
                      }), label: "Monthly repeat")
        switch parsed.monthMode {
        case .each(let day):
            HStack(spacing: 8) {
                Text("Day").font(.system(size: 14)).foregroundStyle(theme.text300)
                KitNumberField(value: Binding(get: { day }, set: { d in edit { $0.monthMode = .each(day: max(1, min(31, d))) } }),
                               range: 1...31, label: "Day of the month")
            }
        case .onThe(let ordinal, let weekday):
            HStack(spacing: 8) {
                KitSelect(options: RecurrenceRule.ordinals.map { (value: $0, label: $0.capitalized) },
                          selection: Binding(get: { ordinal }, set: { o in edit { $0.monthMode = .onThe(ordinal: o, weekday: weekday) } }),
                          label: "Which")
                    .frame(width: 130)
                KitSelect(options: RecurrenceRule.weekdays.map { (value: $0, label: $0.capitalized) },
                          selection: Binding(get: { weekday }, set: { w in edit { $0.monthMode = .onThe(ordinal: ordinal, weekday: w) } }),
                          label: "Day of the week")
                    .frame(width: 160)
            }
        }
    }
}
