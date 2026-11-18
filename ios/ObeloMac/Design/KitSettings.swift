import AppKit
import SwiftUI
import UniformTypeIdentifiers

// The Settings window's pieces (web: settings/index.ejs): a label with its help text beside a control, a list you
// drag into order with a tick on each row, the theme cards, a colour field, and buttons that open the Mac's open
// and save panels.

/// A label and its help text on the left, the control on the right
struct KitSettingRow<Control: View>: View {
    @Environment(\.theme) private var theme
    let title: String
    var detail: String?
    @ViewBuilder var control: Control

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .medium)).foregroundStyle(theme.text200)
                if let detail { Text(detail).font(.system(size: 12)).foregroundStyle(theme.textMuted).fixedSize(horizontal: false, vertical: true) }
            }
            Spacer(minLength: 12)
            control
        }
    }
}

/// One row of a sortable list
struct KitSortItem: Identifiable, Equatable {
    let id: String
    let title: String
    var detail: String?
    var isOn: Bool
    /// Always on and in place (Today, Settings): no handle, no tick
    var isFixed = false
}

/// A list you drag into order (the grip on the left, a drop line shows where it lands) with a tick on each row.
/// ⌥↑ and ⌥↓ move the focused row for the keyboard.
struct KitSortList: View {
    @Environment(\.theme) private var theme
    let items: [KitSortItem]
    /// Without this the rows only switch on and off (no grip, no dragging)
    var reorderable = true
    /// A row moved by this many places (negative is up)
    var onMove: (_ id: String, _ offset: Int) -> Void = { _, _ in }
    let onToggle: (_ id: String) -> Void
    @State private var targeted: String?

    var body: some View {
        VStack(spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                row(item, index: index)
            }
        }
    }

    private func row(_ item: KitSortItem, index: Int) -> some View {
        HStack(spacing: 10) {
            if item.isFixed {
                Image(systemName: "lock.fill").font(.system(size: 10)).foregroundStyle(theme.textMuted).frame(width: 18)
            } else if reorderable {
                KitDragHandle(id: index)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).font(.system(size: 14)).foregroundStyle(item.isFixed || item.isOn ? theme.text100 : theme.textMuted)
                if let detail = item.detail { Text(detail).font(.system(size: 12)).foregroundStyle(theme.textMuted) }
            }
            Spacer(minLength: 8)
            if item.isFixed {
                Text("always on").font(.system(size: 12)).foregroundStyle(theme.textMuted)
            } else {
                KitCheckbox(title: "\(item.title) on", isOn: Binding(get: { item.isOn }, set: { _ in onToggle(item.id) }), showsTitle: false).labelsHidden()
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(theme.elevated, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(theme.border2.opacity(0.6)))
        .kitReorderTarget(isTargeted: Binding(get: { targeted == item.id }, set: { targeted = $0 ? item.id : (targeted == item.id ? nil : targeted) })) { dragged in
            guard reorderable, items.indices.contains(dragged), !items[dragged].isFixed, !item.isFixed else { return false }
            onMove(items[dragged].id, index - dragged)
            return true
        }
        .focusable(!item.isFixed && reorderable)
        .onKeyPress(keys: [.upArrow, .downArrow], phases: .down) { press in
            guard reorderable, !item.isFixed, press.modifiers.contains(.option) else { return .ignored }
            onMove(item.id, press.key == .upArrow ? -1 : 1)
            return .handled
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.isFixed ? "\(item.title), always on" : "\(item.title), \(item.isOn ? "on" : "off")")
        .accessibilityHint(item.isFixed || !reorderable ? "" : "Option up arrow or down arrow moves it")
        .accessibilityAction(named: "Move up") { if reorderable && !item.isFixed { onMove(item.id, -1) } }
        .accessibilityAction(named: "Move down") { if reorderable && !item.isFixed { onMove(item.id, 1) } }
    }
}

/// A theme card: a small preview of the theme's colours and its name (web: `.theme-card`)
struct KitThemeCard: View {
    @Environment(\.theme) private var current
    let name: String
    let detail: String
    /// The theme drawn in the preview
    let preview: Theme
    let isSelected: Bool
    let onSelect: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 4) {
                        RoundedRectangle(cornerRadius: 2).fill(preview.textPrimary).frame(width: 34, height: 4)
                        RoundedRectangle(cornerRadius: 2).fill(preview.textMuted).frame(width: 24, height: 3)
                        Spacer(minLength: 0)
                        RoundedRectangle(cornerRadius: 3).fill(preview.accent).frame(width: 28, height: 8)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .background(preview.page)
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 3).fill(preview.elevated).frame(height: 10)
                        RoundedRectangle(cornerRadius: 3).fill(preview.elevated).frame(height: 10)
                    }
                    .padding(8)
                    .frame(width: 44)
                    .frame(maxHeight: .infinity)
                    .background(preview.surface)
                }
                .frame(height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(preview.border2))
                VStack(alignment: .leading, spacing: 0) {
                    Text(name).font(.system(size: 12, weight: .medium)).foregroundStyle(current.text100).lineLimit(1)
                    Text(detail).font(.system(size: 10)).foregroundStyle(current.textMuted).lineLimit(1)
                }
            }
            .padding(10)
            .background(isSelected ? current.accent.opacity(0.12) : hovering ? current.elevated.opacity(0.6) : .clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(isSelected ? current.accent : current.border2, lineWidth: isSelected ? 2 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name) theme" + (isSelected ? ", selected" : ""))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// An accent colour: a swatch button that opens the system colour panel, with the hex beside it (web: `<input type="color">`)
struct KitColorField: View {
    @Environment(\.theme) private var theme
    @Binding var hex: String
    var label: String

    var body: some View {
        HStack(spacing: 10) {
            KitColorPanel.Button(hex: $hex, label: label) {
                RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color(hex: hex)).frame(width: 44, height: 24)
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(theme.border2, lineWidth: 1))
            }
            Text(hex.lowercased()).font(.system(size: 12, design: .monospaced)).foregroundStyle(theme.textMuted)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }

    static func hex(of color: Color) -> String {
        let n = NSColor(color).usingColorSpace(.sRGB) ?? .black
        return String(format: "#%02x%02x%02x", Int((n.redComponent * 255).rounded()), Int((n.greenComponent * 255).rounded()), Int((n.blueComponent * 255).rounded()))
    }
}

/// A button that opens the Mac's Open panel and hands back what was picked
struct KitFileButton: View {
    let title: String
    var systemImage = "folder"
    let types: [UTType]
    var allowsMultiple = false
    var isBusy = false
    let onPick: ([URL]) -> Void

    var body: some View {
        Button {
            let panel = NSOpenPanel()
            panel.allowedContentTypes = types
            panel.allowsMultipleSelection = allowsMultiple
            panel.canChooseDirectories = false
            panel.begin { response in
                if response == .OK { onPick(panel.urls) }
            }
        } label: {
            if isBusy { ProgressView().controlSize(.small) } else { Label(title, systemImage: systemImage) }
        }
        .buttonStyle(KitButtonStyle(.secondary))
        .disabled(isBusy)
    }
}

enum KitSavePanel {
    /// Asks where to put a file with the Save panel, then writes it. Returns a message for a toast (nil if cancelled).
    @MainActor
    static func save(_ data: Data, as filename: String, completion: @escaping (String?) -> Void) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = filename
        panel.begin { response in
            guard response == .OK, let url = panel.url else { completion(nil); return }
            do { try data.write(to: url, options: .atomic); completion("Saved \(url.lastPathComponent)") }
            catch { completion(error.localizedDescription) }
        }
    }
}

/// The profile picture (the server's own, or a Gravatar), or the first letter of the name on the accent colour
struct KitProfileImage: View {
    @Environment(\.theme) private var theme
    let url: String?
    let name: String
    var size: CGFloat = 56
    @State private var image: NSImage?

    private static var version = 0
    /// Call after the picture changed so the next draw fetches it again
    static func bustCache() { version += 1 }

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                Text(String(name.prefix(1)).uppercased()).font(.system(size: size * 0.43, weight: .semibold)).foregroundStyle(theme.onAccent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity).background(theme.accentDark)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .task(id: "\(url ?? "")|\(Self.version)") { await load() }
        .accessibilityLabel("Your picture")
    }

    private func load() async {
        guard let url, !url.isEmpty else { image = nil; return }
        if url.hasPrefix("/") {
            image = (try? await APIClient.shared.data(path: url)).flatMap(NSImage.init(data:))
        } else if let remote = URL(string: url.replacingOccurrences(of: "s=80", with: "s=160")), let (d, _) = try? await URLSession.shared.data(from: remote) {
            image = NSImage(data: d)
        }
    }

    /// A picked picture as a JPEG no bigger than `maxSide` on its longest side
    static func jpeg(from url: URL, maxSide: CGFloat) -> Data? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let source = NSImage(contentsOf: url), source.size.width > 0 else { return nil }
        let scale = min(1, maxSide / max(source.size.width, source.size.height))
        let size = NSSize(width: source.size.width * scale, height: source.size.height * scale)
        let target = NSImage(size: size)
        target.lockFocus()
        source.draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .copy, fraction: 1)
        target.unlockFocus()
        guard let tiff = target.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85])
    }
}

/// A small round colour swatch that opens the system colour panel when clicked (web: the coloured dot over an
/// `<input type="color">` on the Calendar Sources page). The hex is the value; VoiceOver hears the label.
struct KitColorSwatch: View {
    @Environment(\.theme) private var theme
    @Binding var hex: String
    var label: String
    var size: CGFloat = 14

    var body: some View {
        KitColorPanel.Button(hex: $hex, label: label) {
            Circle().fill(Color(hex: hex)).frame(width: size, height: size)
                .overlay(Circle().strokeBorder(theme.border2, lineWidth: 1))
                .padding(4).contentShape(Circle())
        }
        .help(label)
    }
}

/// The one system colour panel, shared by every colour control. A click on a swatch points the panel at that swatch
/// and brings it to the front, every time (a hidden SwiftUI colour well opened it only some of the time). Changes
/// flow back while you drag in the panel.
@MainActor
enum KitColorPanel {
    private final class Target: NSObject {
        var owner: UUID?
        var onChange: ((String) -> Void)?
        @objc func changed(_ panel: NSColorPanel) {
            onChange?(KitColorField.hex(of: Color(nsColor: panel.color)))
        }
    }
    // Never freed: the panel keeps only a weak reference to its target, so this must outlive every swatch
    private static let target = Target()

    static func show(hex: String, owner: UUID, onChange: @escaping (String) -> Void) {
        let panel = NSColorPanel.shared
        target.onChange = nil
        panel.showsAlpha = false
        panel.isContinuous = true
        panel.color = NSColor(Color(hex: hex))
        target.owner = owner
        target.onChange = onChange
        panel.setTarget(target)
        panel.setAction(#selector(Target.changed(_:)))
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    /// Stops a swatch that is going away from receiving changes
    static func release(owner: UUID) {
        guard target.owner == owner else { return }
        target.onChange = nil; target.owner = nil
    }

    struct Button<Label: View>: View {
        @Binding var hex: String
        let label: String
        @ViewBuilder var content: Label
        @State private var id = UUID()

        var body: some View {
            SwiftUI.Button { KitColorPanel.show(hex: hex, owner: id) { hex = $0 } } label: { content }
                .buttonStyle(.plain)
                .accessibilityLabel(label)
                .accessibilityHint("Opens the colour panel")
                .onDisappear { KitColorPanel.release(owner: id) }
        }
    }
}

/// A row you click to show or hide what is under it ("Calendars to sync (2/3)"), with a turning chevron
/// (web: `<details><summary>`). Opens with Space or Return when focused.
struct KitDisclosure<Content: View>: View {
    @Environment(\.theme) private var theme
    @State private var hovering = false
    let title: String
    @Binding var isOpen: Bool
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { withAnimation(.easeOut(duration: 0.12)) { isOpen.toggle() } } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).rotationEffect(.degrees(isOpen ? 90 : 0))
                        .accessibilityHidden(true)
                    Text(title).font(.system(size: 12))
                }
                .foregroundStyle(hovering ? theme.text300 : theme.textMuted)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .accessibilityValue(isOpen ? "Expanded" : "Collapsed")
            .accessibilityAddTraits(.isButton)
            if isOpen { content }
        }
    }
}
